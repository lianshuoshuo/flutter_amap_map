package dev.hscw.amap_flutter_bridge

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.amap.api.services.core.AMapException
import com.amap.api.services.core.LatLonPoint
import com.amap.api.services.core.PoiItem
import com.amap.api.services.core.ServiceSettings
import com.amap.api.services.geocoder.GeocodeSearch
import com.amap.api.services.geocoder.GeocodeQuery
import com.amap.api.services.geocoder.RegeocodeAddress
import com.amap.api.services.geocoder.RegeocodeQuery
import com.amap.api.services.help.Inputtips
import com.amap.api.services.help.InputtipsQuery
import com.amap.api.services.poisearch.PoiSearch
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class AMapSearchBridge(private val context: Context) {
    private val executor = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private var disposed = false
    private var configured = false

    fun lookup(call: MethodCall, key: String, result: MethodChannel.Result) {
        val latitude = call.argument<Number>("latitude")?.toDouble()
        val longitude = call.argument<Number>("longitude")?.toDouble()
        val radius = call.argument<Int>("radiusMeters")
        if (latitude == null || latitude !in -90.0..90.0 ||
            longitude == null || longitude !in -180.0..180.0 ||
            radius == null || radius !in 1..3000
        ) {
            result.error("invalid_argument", null, null)
            return
        }
        execute(key, result, "geocode_failed", "geocode_no_result") {
            val query = RegeocodeQuery(LatLonPoint(latitude, longitude), radius.toFloat(), GeocodeSearch.AMAP)
            query.extensions = GeocodeSearch.EXTENSIONS_ALL
            GeocodeSearch(context).getFromLocation(query)?.toPayload()
        }
    }

    fun searchPoi(call: MethodCall, key: String, result: MethodChannel.Result) {
        val keyword = call.argument<String>("keyword")?.trim().orEmpty()
        val city = call.argument<String>("city")
        val category = call.argument<String>("categoryCode").orEmpty()
        val pageNumber = call.argument<Int>("page") ?: 1
        val size = call.argument<Int>("pageSize") ?: 20
        val latitude = call.argument<Number>("latitude")?.toDouble()
        val longitude = call.argument<Number>("longitude")?.toDouble()
        val radius = call.argument<Int>("radiusMeters")
        val center = if (radius != null && radius in 1..50000 &&
            latitude != null && latitude in -90.0..90.0 &&
            longitude != null && longitude in -180.0..180.0
        ) LatLonPoint(latitude, longitude) else null
        if (pageNumber !in 1..100 || size !in 1..25 ||
            (radius == null && keyword.isEmpty()) || (radius != null && center == null)) {
            result.error("invalid_argument", null, null)
            return
        }

        execute(key, result, "poi_search_failed") {
            val query = PoiSearch.Query(keyword, category, city).apply {
                pageNum = pageNumber
                pageSize = size
                cityLimit = !city.isNullOrBlank()
            }
            val search = PoiSearch(context, query)
            if (center != null && radius != null) {
                search.bound = PoiSearch.SearchBound(center, radius, true)
            }
            val page = search.searchPOI() ?: return@execute null
            page.pois.orEmpty().map { it.toPayload() }
        }
    }

    fun poiById(call: MethodCall, key: String, result: MethodChannel.Result) {
        val id = call.argument<String>("id")?.trim().orEmpty()
        if (id.isEmpty() || '|' in id) {
            result.error("invalid_argument", null, null)
            return
        }
        execute(key, result, "poi_search_failed") {
            val query = PoiSearch.Query("", "").apply { extensions = PoiSearch.EXTENSIONS_ALL }
            val poi = PoiSearch(context, query).searchPOIId(id)
            listOfNotNull(poi?.toPayload())
        }
    }

    fun forwardGeocode(call: MethodCall, key: String, result: MethodChannel.Result) {
        val address = call.argument<String>("address")?.trim().orEmpty()
        val city = call.argument<String>("city")
        if (address.isEmpty()) {
            result.error("invalid_argument", null, null)
            return
        }
        execute(key, result, "geocode_failed") {
            GeocodeSearch(context).getFromLocationName(GeocodeQuery(address, city))?.map {
                mapOf(
                    "latitude" to it.latLonPoint?.latitude, "longitude" to it.latLonPoint?.longitude,
                    "formattedAddress" to it.formatAddress, "level" to it.level, "country" to it.country,
                    "province" to it.province, "city" to it.city, "district" to it.district,
                    "adCode" to it.adcode, "township" to it.township,
                    "neighborhood" to it.neighborhood, "building" to it.building,
                )
            }
        }
    }

    fun inputTips(call: MethodCall, key: String, result: MethodChannel.Result) {
        val keyword = call.argument<String>("keyword")?.trim().orEmpty()
        val city = call.argument<String>("city")
        val category = call.argument<String>("categoryCode")
        if (keyword.isEmpty()) {
            result.error("invalid_argument", null, null)
            return
        }
        execute(key, result, "poi_search_failed") {
            val query = InputtipsQuery(keyword, city).apply {
                cityLimit = !city.isNullOrBlank()
                if (category != null) type = category
            }
            Inputtips(context, query).requestInputtips()?.map { tip ->
                mapOf(
                    "name" to tip.name, "id" to tip.poiID, "address" to tip.address,
                    "district" to tip.district, "adCode" to tip.adcode, "categoryCode" to tip.typeCode,
                    "latitude" to tip.point?.latitude, "longitude" to tip.point?.longitude,
                )
            }
        }
    }

    private fun execute(
        key: String,
        result: MethodChannel.Result,
        failureCode: String,
        emptyCode: String = failureCode,
        request: () -> Any?,
    ) {
        try {
            if (!configured) {
                ServiceSettings.updatePrivacyShow(context, true, true)
                ServiceSettings.updatePrivacyAgree(context, true)
                ServiceSettings.getInstance().apply {
                    setApiKey(key)
                    setProtocol(ServiceSettings.HTTPS)
                }
                configured = true
            }
        } catch (_: Exception) {
            result.error(failureCode, null, null)
            return
        }

        executor.execute {
            try {
                val data = request()
                main.post {
                    if (!disposed) {
                        if (data == null) result.error(emptyCode, null, null)
                        else result.success(data)
                    }
                }
            } catch (error: AMapException) {
                main.post {
                    if (!disposed) result.error(failureCode, null, error.errorCode)
                }
            } catch (_: Exception) {
                main.post {
                    if (!disposed) result.error(failureCode, null, null)
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        executor.shutdownNow()
    }
}

private fun PoiItem.toPayload() = mapOf(
    "id" to poiId, "name" to title, "address" to snippet,
    "category" to typeDes, "categoryCode" to typeCode,
    "latitude" to latLonPoint?.latitude, "longitude" to latLonPoint?.longitude,
    "province" to provinceName, "city" to cityName, "district" to adName,
    "adCode" to adCode, "telephone" to tel,
)

private fun RegeocodeAddress.toPayload() = mapOf(
    "formattedAddress" to formatAddress,
    "country" to country,
    "province" to province,
    "city" to city,
    "cityCode" to cityCode,
    "district" to district,
    "adCode" to adCode,
    "township" to township,
    "townCode" to towncode,
    "neighborhood" to neighborhood,
    "building" to building,
    "pois" to pois.orEmpty().map {
        mapOf(
            "id" to it.poiId,
            "name" to it.title,
            "type" to it.typeDes,
            "address" to it.snippet,
            "latitude" to it.latLonPoint?.latitude,
            "longitude" to it.latLonPoint?.longitude,
            "distanceMeters" to it.distance,
        )
    },
    "aois" to aois.orEmpty().map {
        mapOf(
            "id" to it.aoiId,
            "name" to it.aoiName,
            "type" to it.type,
            "adCode" to it.adCode,
            "latitude" to it.aoiCenterPoint?.latitude,
            "longitude" to it.aoiCenterPoint?.longitude,
            "distanceMeters" to it.distance.toDouble(),
            "areaSquareMeters" to it.aoiArea?.toDouble(),
        )
    },
)
