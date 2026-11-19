import Flutter
import AMapSearchKit

final class AMapSearchBridge: NSObject, AMapSearchDelegate {
    private var search: AMapSearchAPI?
    private var pending: [ObjectIdentifier: (AMapSearchObject, FlutterResult)] = [:]

    func lookup(_ arguments: Any?, result: @escaping FlutterResult) {
        let args = arguments as? [String: Any]
        guard let latitude = args?["latitude"] as? Double, (-90...90).contains(latitude),
              let longitude = args?["longitude"] as? Double, (-180...180).contains(longitude),
              let radius = args?["radiusMeters"] as? Int, (1...3000).contains(radius) else {
            result(FlutterError(code: "invalid_argument", message: nil, details: nil))
            return
        }
        guard let search = configuredSearch() else {
            result(FlutterError(code: "geocode_failed", message: nil, details: nil))
            return
        }
        let request = AMapReGeocodeSearchRequest()
        request.location = AMapGeoPoint.location(withLatitude: latitude, longitude: longitude)
        request.radius = radius
        request.requireExtension = true
        register(request, result: result, timeoutCode: "geocode_timeout")
        search.aMapReGoecodeSearch(request)
    }

    func searchPoi(_ arguments: Any?, result: @escaping FlutterResult) {
        let args = arguments as? [String: Any]
        let keyword = (args?["keyword"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let page = args?["page"] as? Int ?? 1
        let size = args?["pageSize"] as? Int ?? 20
        let category = args?["categoryCode"] as? String
        guard (1...100).contains(page), (1...25).contains(size) else {
            result(FlutterError(code: "invalid_argument", message: nil, details: nil))
            return
        }
        if let radius = args?["radiusMeters"] as? Int {
            guard (1...50000).contains(radius),
                  let latitude = args?["latitude"] as? Double, (-90...90).contains(latitude),
                  let longitude = args?["longitude"] as? Double, (-180...180).contains(longitude) else {
                result(FlutterError(code: "invalid_argument", message: nil, details: nil))
                return
            }
            guard let search = configuredSearch() else {
                result(FlutterError(code: "poi_search_failed", message: nil, details: nil))
                return
            }
            let request = AMapPOIAroundSearchRequest()
            if !keyword.isEmpty { request.keywords = keyword }
            request.radius = radius
            request.location = AMapGeoPoint.location(withLatitude: latitude, longitude: longitude)
            request.page = page
            request.offset = size
            if let category = category { request.types = category }
            register(request, result: result, timeoutCode: "poi_search_timeout")
            search.aMapPOIAroundSearch(request)
        } else {
            guard !keyword.isEmpty else {
                result(FlutterError(code: "invalid_argument", message: nil, details: nil))
                return
            }
            guard let search = configuredSearch() else {
                result(FlutterError(code: "poi_search_failed", message: nil, details: nil))
                return
            }
            let request = AMapPOIKeywordsSearchRequest()
            request.keywords = keyword
            request.page = page
            request.offset = size
            if let category = category { request.types = category }
            if let city = args?["city"] as? String, !city.isEmpty {
                request.city = city
                request.cityLimit = true
            }
            register(request, result: result, timeoutCode: "poi_search_timeout")
            search.aMapPOIKeywordsSearch(request)
        }
    }

    func poiById(_ arguments: Any?, result: @escaping FlutterResult) {
        let args = arguments as? [String: Any]
        guard let id = (args?["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty, !id.contains("|") else {
            result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return
        }
        guard let search = configuredSearch() else {
            result(FlutterError(code: "poi_search_failed", message: nil, details: nil)); return
        }
        let request = AMapPOIIDSearchRequest()
        request.uid = id
        request.showFieldsType = .business
        register(request, result: result, timeoutCode: "poi_search_timeout")
        search.aMapPOIIDSearch(request)
    }

    func forwardGeocode(_ arguments: Any?, result: @escaping FlutterResult) {
        let args = arguments as? [String: Any]
        guard let address = (args?["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty else {
            result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return
        }
        guard let search = configuredSearch() else {
            result(FlutterError(code: "geocode_failed", message: nil, details: nil)); return
        }
        let request = AMapGeocodeSearchRequest()
        request.address = address
        if let city = args?["city"] as? String { request.city = city }
        register(request, result: result, timeoutCode: "geocode_timeout")
        search.aMapGeocodeSearch(request)
    }

    func inputTips(_ arguments: Any?, result: @escaping FlutterResult) {
        let args = arguments as? [String: Any]
        guard let keyword = (args?["keyword"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !keyword.isEmpty else {
            result(FlutterError(code: "invalid_argument", message: nil, details: nil))
            return
        }
        guard let search = configuredSearch() else {
            result(FlutterError(code: "poi_search_failed", message: nil, details: nil))
            return
        }
        let request = AMapInputTipsSearchRequest()
        request.keywords = keyword
        if let city = args?["city"] as? String, !city.isEmpty {
            request.city = city
            request.cityLimit = true
        }
        if let category = args?["categoryCode"] as? String { request.types = category }
        register(request, result: result, timeoutCode: "poi_search_timeout")
        search.aMapInputTipsSearch(request)
    }

    private func configuredSearch() -> AMapSearchAPI? {
        if search == nil {
            AMapSearchAPI.updatePrivacyShow(.didShow, privacyInfo: .didContain)
            AMapSearchAPI.updatePrivacyAgree(.didAgree)
            search = AMapSearchAPI()
            search?.delegate = self
            search?.timeout = 12
        }
        return search
    }

    private func register(_ request: AMapSearchObject, result: @escaping FlutterResult, timeoutCode: String) {
        let id = ObjectIdentifier(request)
        pending[id] = (request, result)
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self, weak request] in
            guard request != nil else { return }
            self?.finish(id, FlutterError(code: timeoutCode, message: nil, details: nil))
        }
    }

    func onPOISearchDone(_ request: AMapPOISearchBaseRequest!, response: AMapPOISearchResponse!) {
        guard let request = request else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let id = ObjectIdentifier(request)
            guard let response = response else {
                self.finish(id, FlutterError(code: "poi_search_failed", message: nil, details: nil))
                return
            }
            if request is AMapPOIIDSearchRequest && response.count > 0 && (response.pois ?? []).isEmpty {
                self.finish(id, FlutterError(code: "poi_search_failed", message: nil, details: nil)); return
            }
            self.finish(id, (response.pois ?? []).map { poi -> [String: Any] in
                var item = self.point(poi.location)
                item["id"] = poi.uid
                item["name"] = poi.name
                item["address"] = poi.address
                item["category"] = poi.type
                item["categoryCode"] = poi.typecode
                item["province"] = poi.province
                item["city"] = poi.city
                item["district"] = poi.district
                item["adCode"] = poi.adcode
                let businessPhone = poi.businessData?.tel
                item["telephone"] = businessPhone?.isEmpty == false ? businessPhone : poi.tel
                return item
            })
        }
    }

    func onGeocodeSearchDone(_ request: AMapGeocodeSearchRequest!, response: AMapGeocodeSearchResponse!) {
        guard let request = request else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let id = ObjectIdentifier(request)
            guard let response = response, response.count == 0 || !(response.geocodes ?? []).isEmpty else {
                self.finish(id, FlutterError(code: "geocode_failed", message: nil, details: nil)); return
            }
            self.finish(id, (response.geocodes ?? []).map { match -> [String: Any] in
                var item = self.point(match.location)
                item["formattedAddress"] = match.formattedAddress
                item["level"] = match.level
                item["country"] = match.country
                item["province"] = match.province
                item["city"] = match.city
                item["cityCode"] = match.citycode
                item["district"] = match.district
                item["adCode"] = match.adcode
                item["township"] = match.township
                item["neighborhood"] = match.neighborhood
                item["building"] = match.building
                return item
            })
        }
    }

    func onInputTipsSearchDone(_ request: AMapInputTipsSearchRequest!, response: AMapInputTipsSearchResponse!) {
        guard let request = request else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let id = ObjectIdentifier(request)
            guard let response = response else {
                self.finish(id, FlutterError(code: "poi_search_failed", message: nil, details: nil))
                return
            }
            self.finish(id, (response.tips ?? []).map { tip -> [String: Any] in
                var item = self.point(tip.location)
                item["id"] = tip.uid
                item["name"] = tip.name
                item["address"] = tip.address
                item["district"] = tip.district
                item["adCode"] = tip.adcode
                item["categoryCode"] = tip.typecode
                return item
            })
        }
    }

    func onReGeocodeSearchDone(_ request: AMapReGeocodeSearchRequest!, response: AMapReGeocodeSearchResponse!) {
        guard let request = request else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let id = ObjectIdentifier(request)
            if let data = response?.regeocode {
                self.finish(id, self.payload(data))
            } else {
                self.finish(id, FlutterError(code: "geocode_no_result", message: nil, details: nil))
            }
        }
    }

    func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
        guard let request = request as? AMapSearchObject else { return }
        let isGeocode = request is AMapReGeocodeSearchRequest || request is AMapGeocodeSearchRequest
        let code = isGeocode ? "geocode_failed" : "poi_search_failed"
        DispatchQueue.main.async { [weak self] in
            self?.finish(ObjectIdentifier(request),
                FlutterError(code: code, message: nil, details: (error as NSError?)?.code))
        }
    }

    private func finish(_ id: ObjectIdentifier, _ value: Any?) {
        pending.removeValue(forKey: id)?.1(value)
    }

    func dispose() {
        pending.removeAll()
        search?.delegate = nil
        search?.cancelAllRequests()
        search = nil
    }

    private func payload(_ data: AMapReGeocode) -> [String: Any] {
        let area = data.addressComponent
        var result: [String: Any] = [
            "pois": (data.pois ?? []).map { poi -> [String: Any] in
                var item = point(poi.location)
                item["id"] = poi.uid
                item["name"] = poi.name
                item["type"] = poi.type
                item["address"] = poi.address
                item["distanceMeters"] = poi.distance
                return item
            },
            "aois": (data.aois ?? []).map { aoi -> [String: Any] in
                var item = point(aoi.location)
                item["id"] = aoi.uid
                item["name"] = aoi.name
                item["type"] = aoi.type
                item["adCode"] = aoi.adcode
                item["distanceMeters"] = Double(aoi.distance)
                item["areaSquareMeters"] = Double(aoi.area)
                return item
            },
        ]
        result["formattedAddress"] = data.formattedAddress
        result["country"] = area?.country
        result["province"] = area?.province
        result["city"] = area?.city
        result["cityCode"] = area?.citycode
        result["district"] = area?.district
        result["adCode"] = area?.adcode
        result["township"] = area?.township
        result["townCode"] = area?.towncode
        result["neighborhood"] = area?.neighborhood
        result["building"] = area?.building
        return result
    }

    private func point(_ point: AMapGeoPoint?) -> [String: Any] {
        guard let point = point else { return [:] }
        return ["latitude": Double(point.latitude), "longitude": Double(point.longitude)]
    }
}
