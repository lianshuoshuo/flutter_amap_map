import Flutter
import UIKit
import MAMapKit
import AMapFoundationKit

private let viewType = "dev.hscw.amap_flutter_bridge/map"

public class AmapFlutterBridgePlugin: NSObject, FlutterPlugin, FlutterPlatformViewFactory {
    private static var configuredKey: String?
    private let searchBridge = AMapSearchBridge()
    private let messenger: FlutterBinaryMessenger
    private var views: [Int64: WeakMapView] = [:]

    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = AmapFlutterBridgePlugin(messenger: registrar.messenger())
        let channel = FlutterMethodChannel(name: "dev.hscw.amap_flutter_bridge/sdk", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.register(plugin, withId: viewType)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "activeMapCount" { result(views.values.filter { $0.value != nil }.count); return }
        if ["reverseGeocode", "forwardGeocode", "searchPoi", "searchPoiPage", "inputTips", "poiById"].contains(call.method) {
            guard Self.configuredKey != nil else {
                result(FlutterError(code: "sdk_not_initialized", message: nil, details: nil)); return
            }
            switch call.method {
            case "reverseGeocode": searchBridge.lookup(call.arguments, result: result)
            case "forwardGeocode": searchBridge.forwardGeocode(call.arguments, result: result)
            case "inputTips": searchBridge.inputTips(call.arguments, result: result)
            case "poiById": searchBridge.poiById(call.arguments, result: result)
            default: searchBridge.searchPoi(call.arguments, result: result)
            }
            return
        }
        guard call.method == "initialize" else { result(FlutterMethodNotImplemented); return }
        let args = call.arguments as? [String: Any]
        guard args?["privacyAgreed"] as? Bool == true else {
            result(FlutterError(code: "privacy_not_agreed", message: "Consent required", details: nil)); return
        }
        guard let key = args?["apiKey"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result(FlutterError(code: "invalid_argument", message: "Key required", details: nil)); return
        }
        if let existing = Self.configuredKey, existing != key {
            result(FlutterError(code: "initialization_conflict", message: "Key already configured", details: nil)); return
        }
        if Self.configuredKey == nil {
            MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
            MAMapView.updatePrivacyAgree(.didAgree)
            AMapServices.shared().apiKey = key
            Self.configuredKey = key
        }
        result(MAMapKitVersion)
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    public func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let view = AMapNativeView(frame: frame, id: viewId, messenger: messenger,
            args: args as? [String: Any], initialized: Self.configuredKey != nil) { [weak self] in
                self?.views.removeValue(forKey: viewId)
            }
        views[viewId] = WeakMapView(view)
        return view
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        searchBridge.dispose()
        Array(views.values).forEach { $0.value?.dispose() }
    }
}

private class WeakMapView {
    weak var value: AMapNativeView?
    init(_ value: AMapNativeView) { self.value = value }
}

private class MapContainerView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private class AMapNativeView: NSObject, FlutterPlatformView, MAMapViewDelegate, UIGestureRecognizerDelegate {
    private let container: MapContainerView
    private let channel: FlutterMethodChannel
    private struct LineStyle {
        let line: MAPolyline
        let width: CGFloat
        let color: UIColor
    }
    private struct CircleStyle {
        let circle: MACircle
        let width: CGFloat
        let fill: UIColor
        let stroke: UIColor
    }
    private var circles: [String: CircleStyle] = [:]
    private var circleStyles: [ObjectIdentifier: CircleStyle] = [:]
    private var polylines: [String: LineStyle] = [:]
    private var lineStyles: [ObjectIdentifier: LineStyle] = [:]
    private typealias PolygonStyle = (fill: UIColor, stroke: UIColor, width: CGFloat)
    private var polygons: [String: MAPolygon] = [:]
    private var polygonStyles: [ObjectIdentifier: PolygonStyle] = [:]
    private let markers = MarkerStore()
    private var directPanActive = false
    private var sdkUserMotion = false
    private var directPan: UIPanGestureRecognizer?
    private var map: MAMapView?
    private var status = "creating"
    private var disposed = false
    private var hasScreenAnchor = false
    private var active = false
    private var creating = false
    private var snapshotRequested = false
    private let onDisposed: () -> Void

    init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, args: [String: Any]?, initialized: Bool, onDisposed: @escaping () -> Void) {
        container = MapContainerView(frame: frame)
        channel = FlutterMethodChannel(name: "\(viewType)/\(id)", binaryMessenger: messenger)
        self.onDisposed = onDisposed
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
            switch call.method {
            case "updateMarkers":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed" else { result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return }
                do { try self.markers.apply(map, args: call.arguments); result(nil) }
                catch { result(FlutterError(code: "invalid_argument", message: "Invalid marker or PNG", details: nil)) }
            case "updatePolylines":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed" else { result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return }
                result(self.updatePolylines(map, arguments: call.arguments))
            case "updateCircles":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed" else { result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return }
                result(self.updateCircles(map, arguments: call.arguments))
            case "updatePolygons":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed" else { result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return }
                result(self.updatePolygons(map, arguments: call.arguments))
            case "setOptions":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed" else {
                    result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return
                }
                result(self.setOptions(map, arguments: call.arguments))
            case "projectToScreen", "unprojectFromScreen":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed", map.bounds.width > 0, map.bounds.height > 0 else {
                    result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return
                }
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return
                }
                if call.method == "unprojectFromScreen" {
                    guard let x = args["x"] as? Double, let y = args["y"] as? Double,
                          x >= 0, y >= 0, x < self.container.bounds.width, y < self.container.bounds.height else {
                        result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return
                    }
                    let coordinate = map.convert(CGPoint(x: x, y: y), toCoordinateFrom: self.container)
                    guard CLLocationCoordinate2DIsValid(coordinate) else {
                        result(FlutterError(code: "projection_failed", message: nil, details: nil)); return
                    }
                    result(["latitude": coordinate.latitude, "longitude": coordinate.longitude]); return
                }
                guard let lat = args["latitude"] as? Double, (-90...90).contains(lat),
                      let lng = args["longitude"] as? Double, (-180...180).contains(lng) else {
                    result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return
                }
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let point = map.convert(coordinate, toPointTo: self.container)
                guard point.x.isFinite, point.y.isFinite else {
                    result(FlutterError(code: "projection_failed", message: nil, details: nil)); return
                }
                result(["x": Double(point.x), "y": Double(point.y)])
            case "fitBounds":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed", map.bounds.width > 0, map.bounds.height > 0 else {
                    result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return
                }
                result(self.fitBounds(map, arguments: call.arguments))
            case "getCamera", "getZoomRange", "getMapApprovalNumbers", "moveCamera":
                guard !self.disposed else { result(FlutterError(code: "map_disposed", message: nil, details: nil)); return }
                guard let map = self.map, self.status != "failed" else { result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return }
                if call.method == "getCamera" { result(self.cameraData(map)); return }
                if call.method == "getZoomRange" {
                    result(["minZoom": Double(map.minZoomLevel), "maxZoom": Double(map.maxZoomLevel)]); return
                }
                if call.method == "getMapApprovalNumbers" {
                    let content: String? = map.mapContentApprovalNumber()
                    let satellite: String? = map.satelliteImageApprovalNumber()
                    result(["mapContent": content ?? "", "satelliteImage": satellite ?? ""]); return
                }
                guard let args = call.arguments as? [String: Any],
                    let lat = args["latitude"] as? Double, let lng = args["longitude"] as? Double,
                    let zoom = args["zoom"] as? Double, let animated = args["animated"] as? Bool,
                    lat.isFinite, lng.isFinite, zoom.isFinite,
                    (-90...90).contains(lat), (-180...180).contains(lng), (3...20).contains(zoom),
                    Float(zoom) >= Float(map.minZoomLevel), Float(zoom) <= Float(map.maxZoomLevel)
                else { result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return }
                guard let camera = map.getMapStatus() else {
                    result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return
                }
                let rawAnchor = args["targetScreenPoint"]
                if let rawAnchor = rawAnchor {
                    guard map.bounds.width > 0, map.bounds.height > 0 else {
                        result(FlutterError(code: "map_not_ready", message: nil, details: nil)); return
                    }
                    guard let point = rawAnchor as? [String: Any],
                          let x = point["x"] as? Double, x >= 0, x < map.bounds.width,
                          let y = point["y"] as? Double, y >= 0, y < map.bounds.height else {
                        result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return
                    }
                    camera.screenAnchor = CGPoint(x: x / map.bounds.width, y: y / map.bounds.height)
                } else if self.hasScreenAnchor {
                    camera.screenAnchor = CGPoint(x: 0.5, y: 0.5)
                }
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                camera.zoomLevel = CGFloat(zoom)
                self.cameraEvidence("program")
                map.setMapStatus(camera, animated: animated)
                self.hasScreenAnchor = rawAnchor != nil
                result(nil)
            case "getStatus": result(self.status)
            case "setActive":
                self.active = call.arguments as? Bool == true
                if !self.active {
                    self.sdkUserMotion = false
                    self.directPanActive = false
                    self.cameraEvidence("reset")
                }
                self.directPan?.isEnabled = self.active
                self.map?.renderringDisabled = !self.active
                self.requestLoadConfirmation()
                result(nil)
            case "dispose": self.dispose(); result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
        guard initialized, args?["protocolVersion"] as? Int == 1,
            let lat = args?["latitude"] as? Double, let lng = args?["longitude"] as? Double,
            let zoom = args?["zoom"] as? Double, lat.isFinite, lng.isFinite, zoom.isFinite,
            (-90...90).contains(lat), (-180...180).contains(lng), (3...20).contains(zoom)
        else { status = "failed"; return }
        active = args?["active"] as? Bool == true
        container.onLayout = { [weak self] in self?.createMap(latitude: lat, longitude: lng, zoom: zoom) }
        container.setNeedsLayout()
        createMap(latitude: lat, longitude: lng, zoom: zoom)
    }
    private func createMap(latitude: Double, longitude: Double, zoom: Double) {
        guard !disposed, !creating, map == nil, container.bounds.width > 0, container.bounds.height > 0 else { return }
        creating = true
        defer { creating = false }
        let native = MAMapView(frame: container.bounds)
        guard !disposed else { return }
        native.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map = native
        native.minZoomLevel = 3
        native.maxZoomLevel = 20
        native.delegate = self
        native.renderringDisabled = !active
        native.centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        native.zoomLevel = CGFloat(zoom)
        guard !disposed else { return }
        container.addSubview(native)
        guard !disposed, map === native else { return }
        if status == "creating" {
            status = "ready"
            channel.invokeMethod("status", arguments: status)
        }
        requestLoadConfirmation()
    }
    private func requestLoadConfirmation() {
        guard active, !disposed, !snapshotRequested, status != "failed", status != "loaded", map != nil else { return }
        snapshotRequested = true
        // The SDK snapshot supplies another explicit full-load signal.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.disposed else { return }
            guard self.active else { self.snapshotRequested = false; return }
            guard self.status != "failed", self.status != "loaded", let map = self.map else { return }
            map.takeSnapshot(in: map.bounds, timeoutInterval: 10) { [weak self] image, state in
                guard state == 1, image != nil else { return }
                DispatchQueue.main.async { self?.markLoaded() }
            }
        }
    }
    func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
        guard !disposed, let marker = annotation as? BridgeMarker,
              markers.entries[marker.markerId] === marker else { return nil }
        let view = MAAnnotationView(annotation: marker, reuseIdentifier: nil)!
        view.image = marker.image
        view.centerOffset = marker.offset
        view.transform = CGAffineTransform(rotationAngle: marker.angle)
        view.zIndex = marker.order
        view.isHidden = !marker.visible
        view.isEnabled = marker.visible
        view.canShowCallout = false
        return view
    }
    func mapView(_ mapView: MAMapView!, didSingleTappedAt coordinate: CLLocationCoordinate2D) {
        onCameraMain(mapView) { [weak self] _ in
            self?.channel.invokeMethod("mapTap", arguments: [
                "latitude": coordinate.latitude, "longitude": coordinate.longitude
            ])
        }
    }

    func mapView(_ mapView: MAMapView!, didSelect view: MAAnnotationView!) {
        guard !disposed, let marker = view.annotation as? BridgeMarker, marker.visible,
              markers.entries[marker.markerId] === marker else { return }
        channel.invokeMethod("markerTap", arguments: marker.markerId)
        mapView.deselectAnnotation(marker, animated: false)
    }
    private func setOptions(_ map: MAMapView, arguments: Any?) -> FlutterError? {
        guard let args = arguments as? [String: Any],
              let type = args["mapType"] as? String, type == "standard" || type == "satellite",
              let scroll = args["scrollEnabled"] as? Bool,
              let zoom = args["zoomEnabled"] as? Bool,
              let rotate = args["rotateEnabled"] as? Bool,
              let tilt = args["tiltEnabled"] as? Bool,
              let inertia = args["inertiaEnabled"] as? Bool,
              let compass = args["compassEnabled"] as? Bool,
              let scale = args["scaleEnabled"] as? Bool,
              let zoomControls = args["zoomControlsEnabled"] as? Bool,
              let buildings = (args["buildingsEnabled"] ?? true) as? Bool,
              let min = (args["minZoom"] ?? 3.0) as? Double,
              let max = (args["maxZoom"] ?? 20.0) as? Double,
              min >= 3, max <= 20, min <= max else {
            return FlutterError(code: "invalid_argument", message: "Invalid map options", details: nil)
        }
        if zoomControls {
            return FlutterError(code: "unsupported_option", message: "iOS has no native zoom buttons", details: nil)
        }
        let mapType: MAMapType = type == "satellite" ? .satellite : .standard
        let oldType = map.mapType
        let oldMin = map.minZoomLevel
        let oldMax = map.maxZoomLevel
        cameraEvidence("reset")
        if oldType != mapType { map.mapType = mapType }
        writeZoomRange(map, min: CGFloat(min), max: CGFloat(max))
        guard Float(map.minZoomLevel) >= Float(min), Float(map.maxZoomLevel) <= Float(max),
              map.minZoomLevel <= map.maxZoomLevel else {
            if oldType != mapType { map.mapType = oldType }
            writeZoomRange(map, min: oldMin, max: oldMax)
            return FlutterError(code: "unsupported_option", message: "SDK cannot apply this zoom range", details: nil)
        }
        sdkUserMotion = false
        directPanActive = false
        map.isScrollEnabled = scroll && inertia
        map.isZoomEnabled = zoom
        map.isRotateEnabled = rotate
        map.isRotateCameraEnabled = tilt
        map.showsCompass = compass
        map.showsScale = scale
        if scroll && !inertia {
            if directPan == nil {
                let pan = UIPanGestureRecognizer(target: self, action: #selector(panWithoutInertia(_:)))
                pan.maximumNumberOfTouches = 1
                pan.isEnabled = active
                pan.delegate = self
                map.addGestureRecognizer(pan)
                directPan = pan
            }
        } else if let pan = directPan {
            map.removeGestureRecognizer(pan)
            directPan = nil
        }
        map.isShowsBuildings = buildings
        let bounded = Swift.max(map.minZoomLevel, Swift.min(map.zoomLevel, map.maxZoomLevel))
        if map.zoomLevel != bounded {
            cameraEvidence("program")
            map.setZoomLevel(bounded, animated: false)
        }
        return nil
    }

    private func writeZoomRange(_ map: MAMapView, min: CGFloat, max: CGFloat) {
        if min < map.minZoomLevel { map.minZoomLevel = min }
        if max != map.maxZoomLevel { map.maxZoomLevel = max }
        if min != map.minZoomLevel { map.minZoomLevel = min }
    }

    // Let the SDK receive two-finger gestures if a second finger joins a direct pan.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return gestureRecognizer === directPan || otherGestureRecognizer === directPan
    }

    @objc private func panWithoutInertia(_ pan: UIPanGestureRecognizer) {
        guard active, !disposed, let map = map, pan === directPan else { return }
        if pan.state == .began {
            directPanActive = true
            cameraEvidence("start", map: map)
            cameraEvidence("drag")
        }
        if pan.state == .cancelled || pan.state == .failed {
            directPanActive = false
            cameraEvidence("cancel")
            return
        }
        guard directPanActive else { return }
        let delta = pan.translation(in: map)
        pan.setTranslation(.zero, in: map)
        if delta != .zero {
            let point = map.convert(map.centerCoordinate, toPointTo: map)
            let next = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
            let center = map.convert(next, toCoordinateFrom: map)
            if CLLocationCoordinate2DIsValid(center) { map.centerCoordinate = center }
        }
        if pan.state == .ended {
            directPanActive = false
            cameraEvidence("end")
        }
    }

    private func fitBounds(_ map: MAMapView, arguments: Any?) -> FlutterError? {
        let invalid = FlutterError(code: "invalid_argument", message: "Invalid bounds or padding", details: nil)
        guard let args = arguments as? [String: Any],
              let south = args["south"] as? Double, let north = args["north"] as? Double,
              let west = args["west"] as? Double, let east = args["east"] as? Double,
              south >= -85.05112878, north <= 85.05112878, south < north,
              west >= -180, east <= 180, west < east, east - west <= 180,
              let left = args["left"] as? Double, let right = args["right"] as? Double,
              let top = args["top"] as? Double, let bottom = args["bottom"] as? Double,
              left >= 0, right >= 0, top >= 0, bottom >= 0,
              left + right < map.bounds.width, top + bottom < map.bounds.height,
              let animated = args["animated"] as? Bool else { return invalid }
        let sw = MAMapPointForCoordinate(CLLocationCoordinate2D(latitude: south, longitude: west))
        let ne = MAMapPointForCoordinate(CLLocationCoordinate2D(latitude: north, longitude: east))
        let rect = MAMapRectMake(min(sw.x, ne.x), min(sw.y, ne.y), abs(ne.x - sw.x), abs(ne.y - sw.y))
        let padding = UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        cameraEvidence("program")
        if hasScreenAnchor {
            map.screenAnchor = CGPoint(x: 0.5, y: 0.5)
            hasScreenAnchor = false
        }
        map.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
        return nil
    }

    private func updatePolylines(_ map: MAMapView, arguments: Any?) -> FlutterError? {
        let invalid = FlutterError(code: "invalid_argument", message: "Invalid polyline", details: nil)
        guard let batch = arguments as? [String: Any],
              let upsert = batch["upsert"] as? [[String: Any]],
              let remove = batch["remove"] as? [String] else { return invalid }
        var staged: [String: LineStyle] = [:]
        for item in upsert {
            guard let id = item["id"] as? String, !id.isEmpty, staged[id] == nil, !remove.contains(id),
                  let width = item["width"] as? Double, (1...128).contains(width),
                  let argb = item["color"] as? Int32,
                  let points = item["points"] as? [[Double]], points.count >= 2,
                  var coordinates = decodePoints(points) else { return invalid }
            let line = coordinates.withUnsafeMutableBufferPointer {
                MAPolyline(coordinates: $0.baseAddress, count: UInt($0.count))
            }
            guard let line = line else {
                return FlutterError(code: "native_error", message: "Polyline creation failed", details: nil)
            }
            staged[id] = LineStyle(line: line, width: CGFloat(width), color: colorFromARGB(argb))
        }
        for id in remove + Array(staged.keys) {
            if let old = polylines.removeValue(forKey: id) {
                lineStyles.removeValue(forKey: ObjectIdentifier(old.line))
                map.remove(old.line)
            }
        }
        for (id, style) in staged {
            polylines[id] = style
            lineStyles[ObjectIdentifier(style.line)] = style
            map.add(style.line)
        }
        return nil
    }

    private func colorFromARGB(_ value: Int32) -> UIColor {
        let bits = UInt32(bitPattern: value)
        return UIColor(red: CGFloat((bits >> 16) & 255) / 255,
                       green: CGFloat((bits >> 8) & 255) / 255,
                       blue: CGFloat(bits & 255) / 255,
                       alpha: CGFloat(bits >> 24) / 255)
    }

    private func decodePoints(_ points: [[Double]]) -> [CLLocationCoordinate2D]? {
        var coordinates: [CLLocationCoordinate2D] = []
        for point in points {
            guard point.count == 2, (-90...90).contains(point[0]),
                  (-180...180).contains(point[1]) else { return nil }
            coordinates.append(CLLocationCoordinate2D(latitude: point[0], longitude: point[1]))
        }
        return coordinates
    }

    private func updatePolygons(_ map: MAMapView, arguments: Any?) -> FlutterError? {
        let invalid = FlutterError(code: "invalid_argument", message: "Invalid polygon", details: nil)
        guard let batch = arguments as? [String: Any], let upsert = batch["upsert"] as? [[String: Any]],
              let remove = batch["remove"] as? [String] else { return invalid }
        var changes: [String: (points: [CLLocationCoordinate2D], style: PolygonStyle)] = [:]
        for item in upsert {
            guard let id = item["id"] as? String, !id.isEmpty, changes[id] == nil, !remove.contains(id),
                  let points = item["points"] as? [[Double]], Set(points).count >= 3,
                  let coordinates = decodePoints(points),
                  let width = item["strokeWidth"] as? Double, (1...128).contains(width),
                  let fill = item["fillColor"] as? Int32, let stroke = item["strokeColor"] as? Int32 else { return invalid }
            changes[id] = (coordinates, (colorFromARGB(fill), colorFromARGB(stroke), CGFloat(width)))
        }
        for (id, change) in changes {
            var coordinates = change.points
            if let shape = polygons[id] {
                let updated = coordinates.withUnsafeMutableBufferPointer {
                    shape.setPolygonWithCoordinates($0.baseAddress, count: $0.count)
                }
                guard updated else { return FlutterError(code: "native_error", message: "Polygon update failed", details: nil) }
                polygonStyles[ObjectIdentifier(shape)] = change.style
                if let renderer = map.renderer(for: shape) as? MAPolygonRenderer {
                    applyPolygonStyle(change.style, to: renderer)
                    renderer.setNeedsUpdate()
                }
            } else {
                let polygon = coordinates.withUnsafeMutableBufferPointer {
                    MAPolygon(coordinates: $0.baseAddress, count: UInt($0.count))
                }
                guard let shape = polygon else { return FlutterError(code: "native_error", message: "Polygon creation failed", details: nil) }
                polygons[id] = shape
                polygonStyles[ObjectIdentifier(shape)] = change.style
                map.add(shape)
            }
        }
        for id in remove {
            if let shape = polygons.removeValue(forKey: id) {
                map.remove(shape)
                polygonStyles.removeValue(forKey: ObjectIdentifier(shape))
            }
        }
        return nil
    }

    private func applyPolygonStyle(_ style: PolygonStyle, to renderer: MAPolygonRenderer) {
        renderer.fillColor = style.fill
        renderer.strokeColor = style.stroke
        renderer.lineWidth = style.width
    }

    private func updateCircles(_ map: MAMapView, arguments: Any?) -> FlutterError? {
        let invalid = FlutterError(code: "invalid_argument", message: "Invalid circle", details: nil)
        guard let batch = arguments as? [String: Any],
              let upsert = batch["upsert"] as? [[String: Any]],
              let remove = batch["remove"] as? [String] else { return invalid }
        var staged: [String: CircleStyle] = [:]
        for item in upsert {
            guard let id = item["id"] as? String, !id.isEmpty, staged[id] == nil, !remove.contains(id),
                  let latitude = item["latitude"] as? Double, (-90...90).contains(latitude),
                  let longitude = item["longitude"] as? Double, (-180...180).contains(longitude),
                  let radius = item["radiusMeters"] as? Double, radius.isFinite, radius > 0,
                  let width = item["strokeWidth"] as? Double, (1...128).contains(width),
                  let fill = item["fillColor"] as? Int32,
                  let stroke = item["strokeColor"] as? Int32 else { return invalid }
            guard let circle = MACircle(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                        radius: radius) else {
                return FlutterError(code: "native_error", message: "Circle creation failed", details: nil)
            }
            staged[id] = CircleStyle(circle: circle, width: CGFloat(width),
                                     fill: colorFromARGB(fill), stroke: colorFromARGB(stroke))
        }
        for id in remove + Array(staged.keys) {
            if let old = circles.removeValue(forKey: id) {
                circleStyles.removeValue(forKey: ObjectIdentifier(old.circle))
                map.remove(old.circle)
            }
        }
        for (id, style) in staged {
            circles[id] = style
            circleStyles[ObjectIdentifier(style.circle)] = style
            map.add(style.circle)
        }
        return nil
    }

    func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
        guard !disposed, mapView === map else { return nil }
        if let shape = overlay as? MAPolygon, let style = polygonStyles[ObjectIdentifier(shape)],
           let renderer = MAPolygonRenderer(polygon: shape) {
            applyPolygonStyle(style, to: renderer)
            return renderer
        }
        if let circle = overlay as? MACircle,
           let style = circleStyles[ObjectIdentifier(circle)],
           let renderer = MACircleRenderer(circle: circle) {
            renderer.fillColor = style.fill
            renderer.strokeColor = style.stroke
            renderer.lineWidth = style.width
            return renderer
        }
        guard let line = overlay as? MAPolyline,
              let style = lineStyles[ObjectIdentifier(line)],
              let renderer = MAPolylineRenderer(polyline: line) else { return nil }
        renderer.strokeColor = style.color
        renderer.lineWidth = style.width
        return renderer
    }

    private func cameraData(_ map: MAMapView) -> [String: Double] {
        ["latitude": map.centerCoordinate.latitude, "longitude": map.centerCoordinate.longitude,
         "zoom": Double(map.zoomLevel), "bearing": Double(map.rotationDegree), "tilt": Double(map.cameraDegree)]
    }
    private func cameraEvent(_ mapView: MAMapView?, method: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self, weak mapView] in self?.cameraEvent(mapView, method: method) }
            return
        }
        guard active, !disposed, let mapView = mapView, map === mapView else { return }
        channel.invokeMethod(method, arguments: cameraData(mapView))
    }
    func mapViewRegionChanged(_ mapView: MAMapView!) { cameraEvent(mapView, method: "cameraMove") }
    private func cameraEvidence(_ kind: String, map: MAMapView? = nil) {
        var data: [String: Any] = map.map { cameraData($0) } ?? [:]
        data["kind"] = kind
        channel.invokeMethod("cameraEvidence", arguments: data)
    }

    private func onCameraMain(_ mapView: MAMapView?, _ action: @escaping (MAMapView) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self, weak mapView] in self?.onCameraMain(mapView, action) }
            return
        }
        guard active, !disposed, let mapView = mapView, map === mapView else { return }
        action(mapView)
    }

    func mapView(_ mapView: MAMapView!, regionWillChangeAnimated animated: Bool, wasUserAction: Bool) {
        guard wasUserAction else { return }
        onCameraMain(mapView) { [weak self] native in self?.startSDKUserMotion(native) }
    }

    func mapView(_ mapView: MAMapView!, mapWillMoveByUser wasUserAction: Bool) {
        guard wasUserAction else { return }
        onCameraMain(mapView) { [weak self] native in
            guard let self, !self.directPanActive else { return }
            self.startSDKUserMotion(native)
            self.cameraEvidence("drag")
        }
    }

    func mapView(_ mapView: MAMapView!, mapWillZoomByUser wasUserAction: Bool) {
        guard wasUserAction else { return }
        onCameraMain(mapView) { [weak self] native in
            guard let self else { return }
            self.startSDKUserMotion(native)
            self.cameraEvidence("multi")
        }
    }

    private func startSDKUserMotion(_ native: MAMapView) {
        guard !sdkUserMotion, !directPanActive else { return }
        sdkUserMotion = true
        cameraEvidence("start", map: native)
    }

    func mapView(_ mapView: MAMapView!, regionDidChangeAnimated animated: Bool, wasUserAction: Bool) {
        onCameraMain(mapView) { [weak self] native in
            guard let self else { return }
            if self.sdkUserMotion {
                self.sdkUserMotion = false
                self.cameraEvidence(wasUserAction ? "end" : "cancel")
            }
            self.cameraEvent(native, method: "cameraIdle")
        }
    }
    func view() -> UIView { container }
    func mapViewDidFinishLoadingMap(_ mapView: MAMapView!) {
        DispatchQueue.main.async { [weak self, weak mapView] in
            guard let self = self, let mapView = mapView, self.map === mapView else { return }
            self.markLoaded()
        }
    }
    private func markLoaded() {
        guard !disposed, status != "failed", status != "loaded" else { return }
        status = "loaded"
        channel.invokeMethod("status", arguments: status)
    }
    func mapViewDidFailLoadingMap(_ mapView: MAMapView!, withError error: Error!) {
        let nativeError = error as NSError?
        DispatchQueue.main.async { [weak self, weak mapView] in
            guard let self = self, !self.disposed, let mapView = mapView, self.map === mapView else { return }
            if let nativeError = nativeError {
                NSLog("AMap map load failed: domain=%@ code=%ld", nativeError.domain, nativeError.code)
            }
            self.status = "failed"
            self.channel.invokeMethod("status", arguments: self.status)
        }
    }
    func dispose() {
        guard !disposed else { return }
        disposed = true
        container.onLayout = nil
        if let pan = directPan { map?.removeGestureRecognizer(pan) }
        directPan = nil
        map?.delegate = nil
        markers.clear(map)
        for style in polylines.values { map?.remove(style.line) }
        polylines.removeAll()
        lineStyles.removeAll()
        for polygon in polygons.values { map?.remove(polygon) }
        polygons.removeAll()
        polygonStyles.removeAll()
        for style in circles.values { map?.remove(style.circle) }
        circles.removeAll()
        circleStyles.removeAll()
        map?.removeFromSuperview()
        map = nil
        channel.setMethodCallHandler(nil)
        onDisposed()
    }
    deinit { dispose() }
}
