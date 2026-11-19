package dev.hscw.amap_flutter_bridge

import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.Point
import android.os.Bundle
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.View
import android.widget.FrameLayout
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.amap.api.maps.AMap
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.model.Circle
import com.amap.api.maps.model.CircleOptions
import com.amap.api.maps.model.Polyline
import com.amap.api.maps.model.PolylineOptions
import com.amap.api.maps.model.Polygon
import com.amap.api.maps.model.PolygonOptions
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.LatLngBounds
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.roundToInt

private const val VIEW_TYPE = "dev.hscw.amap_flutter_bridge/map"

class AmapFlutterBridgePlugin : FlutterPlugin, ActivityAware, Application.ActivityLifecycleCallbacks {
    companion object { private var configuredKey: String? = null }
    private lateinit var searchBridge: AMapSearchBridge
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var application: Application? = null
    private var activityResumed = false
    private val views = mutableSetOf<AMapNativeView>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        searchBridge = AMapSearchBridge(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "dev.hscw.amap_flutter_bridge/sdk")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val key = call.argument<String>("apiKey")
                    when {
                        call.argument<Boolean>("privacyAgreed") != true -> result.error("privacy_not_agreed", "Consent required", null)
                        key.isNullOrBlank() -> result.error("invalid_argument", "Key required", null)
                        configuredKey != null && configuredKey != key -> result.error("initialization_conflict", "Key already configured", null)
                        else -> try {
                            if (configuredKey == null) {
                                MapsInitializer.updatePrivacyShow(binding.applicationContext, true, true)
                                MapsInitializer.updatePrivacyAgree(binding.applicationContext, true)
                                MapsInitializer.setApiKey(key)
                                MapsInitializer.initialize(binding.applicationContext)
                                configuredKey = key
                            }
                            result.success(MapsInitializer.getVersion())
                        } catch (_: Exception) {
                            result.error("native_error", "SDK initialization failed", null)
                        }
                    }
                }
                "reverseGeocode", "forwardGeocode", "searchPoi", "searchPoiPage", "inputTips", "poiById" -> {
                    val key = configuredKey
                    if (key == null) result.error("sdk_not_initialized", null, null)
                    else when (call.method) {
                        "reverseGeocode" -> searchBridge.lookup(call, key, result)
                        "forwardGeocode" -> searchBridge.forwardGeocode(call, key, result)
                        "inputTips" -> searchBridge.inputTips(call, key, result)
                        "poiById" -> searchBridge.poiById(call, key, result)
                        else -> searchBridge.searchPoi(call, key, result)
                    }
                }
                "activeMapCount" -> result.success(views.size)
                else -> result.notImplemented()
            }
        }
        binding.platformViewRegistry.registerViewFactory(VIEW_TYPE,
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val view = AMapNativeView(activity ?: context, binding.binaryMessenger, viewId,
                        args as? Map<*, *>, configuredKey != null) { views.remove(it) }
                    views.add(view)
                    if (activityResumed) view.resume()
                    return view
                }
            })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        views.toList().forEach { it.dispose() }
        searchBridge.dispose()
        channel.setMethodCallHandler(null)
        detachActivity()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        application = binding.activity.application
        application?.registerActivityLifecycleCallbacks(this)
        activityResumed = (binding.activity as? LifecycleOwner)?.lifecycle?.currentState
            ?.isAtLeast(Lifecycle.State.RESUMED) == true
        if (activityResumed) views.forEach { it.resume() }
    }
    private fun detachActivity() {
        application?.unregisterActivityLifecycleCallbacks(this)
        application = null
        activity = null
        activityResumed = false
        views.forEach { it.pause() }
    }
    override fun onDetachedFromActivity() = detachActivity()
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onActivityResumed(a: Activity) { if (a === activity) { activityResumed = true; views.forEach { it.resume() } } }
    override fun onActivityPaused(a: Activity) { if (a === activity) { activityResumed = false; views.forEach { it.pause() } } }
    override fun onActivityCreated(a: Activity, state: Bundle?) {}
    override fun onActivityStarted(a: Activity) {}
    override fun onActivityStopped(a: Activity) {}
    override fun onActivitySaveInstanceState(a: Activity, state: Bundle) {}
    override fun onActivityDestroyed(a: Activity) { if (a === activity) views.toList().forEach { it.dispose() } }
}

private class AMapNativeView(
    context: Context, messenger: BinaryMessenger, id: Int, args: Map<*, *>?, initialized: Boolean,
    private val onDisposed: (AMapNativeView) -> Unit
) : PlatformView {
    private val circles = mutableMapOf<String, Circle>()
    private val polylines = mutableMapOf<String, Polyline>()
    private val polygons = mutableMapOf<String, Polygon>()
    private val markers = MarkerStore(context.resources.displayMetrics.density)
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "$VIEW_TYPE/$id")
    private var mapView: MapView? = null
    private var status = "creating"
    private var disposed = false
    private var resumed = false
    private enum class ScreenAnchorMode { SDK_DEFAULT, CUSTOM, CENTERED }
    private var screenAnchorMode = ScreenAnchorMode.SDK_DEFAULT

    private var dragX = 0f
    private var dragY = 0f
    private var directDragEnabled = false
    private var trackingDrag = false
    private var dragging = false
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    private val zoomTapDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent): Boolean = true
        override fun onDoubleTap(event: MotionEvent): Boolean {
            if (!disposed) cameraEvidence("zoom")
            return true
        }
    })

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateMarkers" -> {
                    val map = mapView?.map
                    if (disposed) result.error("map_disposed", null, null)
                    else if (map == null || status == "creating" || status == "failed") result.error("map_not_ready", null, null)
                    else try {
                        markers.apply(map, call.arguments as? Map<*, *> ?: throw IllegalArgumentException())
                        result.success(null)
                    } catch (_: IllegalArgumentException) { result.error("invalid_argument", null, null) }
                    catch (_: Exception) { result.error("native_error", null, null) }
                }
                "updatePolylines" -> {
                    val map = mapView?.map
                    if (disposed) result.error("map_disposed", null, null)
                    else if (map == null || status == "creating" || status == "failed") result.error("map_not_ready", null, null)
                    else try {
                        updatePolylines(map, call.arguments as? Map<*, *> ?: throw IllegalArgumentException())
                        result.success(null)
                    } catch (_: IllegalArgumentException) { result.error("invalid_argument", null, null) }
                    catch (_: Exception) { result.error("native_error", null, null) }
                }
                "updateCircles", "updatePolygons" -> {
                    val map = mapView?.map
                    if (disposed) result.error("map_disposed", null, null)
                    else if (map == null || status == "creating" || status == "failed") result.error("map_not_ready", null, null)
                    else try {
                        val batch = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
                        if (call.method == "updatePolygons") updatePolygons(map, batch) else updateCircles(map, batch)
                        result.success(null)
                    } catch (_: IllegalArgumentException) { result.error("invalid_argument", null, null) }
                    catch (_: Exception) { result.error("native_error", null, null) }
                }
                "setOptions" -> {
                    val map = mapView?.map
                    if (disposed) result.error("map_disposed", null, null)
                    else if (map == null || status == "creating" || status == "failed") result.error("map_not_ready", null, null)
                    else try {
                        setOptions(map, call.arguments as? Map<*, *> ?: throw IllegalArgumentException())
                        result.success(null)
                    } catch (_: IllegalArgumentException) { result.error("invalid_argument", null, null) }
                    catch (_: UnsupportedOperationException) { result.error("unsupported_option", null, null) }
                    catch (_: Exception) { result.error("native_error", null, null) }
                }
                "projectToScreen", "unprojectFromScreen" -> {
                    val view = mapView
                    if (disposed) result.error("map_disposed", null, null)
                    else if (view == null || status == "creating" || status == "failed" ||
                        view.width <= 0 || view.height <= 0) result.error("map_not_ready", null, null)
                    else try {
                        val density = view.resources.displayMetrics.density.toDouble()
                        val projection = view.map.projection
                        if (call.method == "unprojectFromScreen") {
                            val x = call.argument<Number>("x")?.toDouble()
                            val y = call.argument<Number>("y")?.toDouble()
                            require(x != null && y != null && x >= 0 && y >= 0 &&
                                x * density < view.width && y * density < view.height)
                            val point = Point((x * density).roundToInt().coerceAtMost(view.width - 1),
                                (y * density).roundToInt().coerceAtMost(view.height - 1))
                            val coordinate = projection.fromScreenLocation(point)
                            if (coordinate == null || coordinate.latitude !in -90.0..90.0 || coordinate.longitude !in -180.0..180.0)
                                result.error("projection_failed", null, null)
                            else result.success(mapOf("latitude" to coordinate.latitude, "longitude" to coordinate.longitude))
                        } else {
                            val lat = call.argument<Number>("latitude")?.toDouble()
                            val lng = call.argument<Number>("longitude")?.toDouble()
                            require(lat != null && lat in -90.0..90.0 && lng != null && lng in -180.0..180.0)
                            val point = projection.toScreenLocation(LatLng(lat, lng))
                            if (point == null) result.error("projection_failed", null, null)
                            else result.success(mapOf("x" to point.x / density, "y" to point.y / density))
                        }
                    } catch (_: IllegalArgumentException) { result.error("invalid_argument", null, null) }
                    catch (_: Exception) { result.error("projection_failed", null, null) }
                }
                "fitBounds" -> {
                    val view = mapView
                    if (disposed) result.error("map_disposed", null, null)
                    else if (view == null || status == "creating" || status == "failed" ||
                        view.width <= 0 || view.height <= 0) result.error("map_not_ready", null, null)
                    else try {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
                        fitBounds(view, args)
                        result.success(null)
                    } catch (_: IllegalArgumentException) { result.error("invalid_argument", null, null) }
                    catch (_: Exception) { result.error("native_error", null, null) }
                }
                "getCamera", "getZoomRange", "getMapApprovalNumbers", "moveCamera" -> {
                    val view = mapView
                    val map = view?.map
                    when {
                        disposed -> result.error("map_disposed", null, null)
                        map == null || status == "creating" || status == "failed" -> result.error("map_not_ready", null, null)
                        else -> try {
                            if (call.method == "getCamera") result.success(cameraData(map.cameraPosition))
                            else if (call.method == "getZoomRange") result.success(mapOf(
                                "minZoom" to map.minZoomLevel.toDouble(), "maxZoom" to map.maxZoomLevel.toDouble()))
                            else if (call.method == "getMapApprovalNumbers") result.success(mapOf(
                                "mapContent" to map.mapContentApprovalNumber, "satelliteImage" to map.satelliteImageApprovalNumber))
                            else {
                                val lat = call.argument<Number>("latitude")?.toDouble()
                                val lng = call.argument<Number>("longitude")?.toDouble()
                                val zoom = call.argument<Number>("zoom")?.toDouble()
                                val animated = call.argument<Boolean>("animated")
                                require(lat != null && lat.isFinite() && lat in -90.0..90.0 &&
                                    lng != null && lng.isFinite() && lng in -180.0..180.0 &&
                                    zoom != null && zoom in 3.0..20.0 &&
                                    zoom.toFloat() in map.minZoomLevel..map.maxZoomLevel && animated != null)
                                val rawAnchor = call.argument<Any>("targetScreenPoint")
                                if ((rawAnchor != null || screenAnchorMode != ScreenAnchorMode.SDK_DEFAULT) && (view.width <= 0 || view.height <= 0)) {
                                    result.error("map_not_ready", null, null)
                                    return@setMethodCallHandler
                                }
                                val anchor = rawAnchor?.let {
                                    val point = it as? Map<*, *> ?: throw IllegalArgumentException()
                                    val x = (point["x"] as? Number)?.toDouble()
                                    val y = (point["y"] as? Number)?.toDouble()
                                    val density = view.resources.displayMetrics.density.toDouble()
                                    require(x != null && x >= 0 && x * density < view.width &&
                                        y != null && y >= 0 && y * density < view.height)
                                    Point((x * density).roundToInt().coerceAtMost(view.width - 1),
                                        (y * density).roundToInt().coerceAtMost(view.height - 1))
                                }
                                val update = CameraUpdateFactory.newLatLngZoom(LatLng(lat, lng), zoom.toFloat())
                                cameraEvidence("program")
                                setScreenAnchor(view, anchor)
                                if (animated) map.animateCamera(update) else map.moveCamera(update)
                                result.success(null)
                            }
                        } catch (_: IllegalArgumentException) { result.error("invalid_argument", null, null) }
                        catch (_: Exception) { result.error("native_error", null, null) }
                    }
                }
                "getStatus" -> result.success(status)
                "setActive" -> { if (call.arguments == true) resume() else pause(); result.success(null) }
                "dispose" -> { dispose(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        if (!initialized || args?.get("protocolVersion") != 1) {
            status = "failed"
        } else try {
            val lat = (args["latitude"] as Number).toDouble()
            val lng = (args["longitude"] as Number).toDouble()
            val zoom = (args["zoom"] as Number).toFloat()
            require(lat.isFinite() && lat in -90.0..90.0 && lng.isFinite() && lng in -180.0..180.0 && zoom in 3f..20f)
            val view = MapView(context)
            mapView = view
            view.onCreate(null)
            container.addView(view, FrameLayout.LayoutParams(-1, -1))
            view.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
                val width = right - left
                val height = bottom - top
                if (!disposed && screenAnchorMode == ScreenAnchorMode.CENTERED && width > 0 && height > 0 &&
                    (width != oldRight - oldLeft || height != oldBottom - oldTop)) {
                    view.map.setPointToCenter(width / 2, height / 2)
                }
            }
            view.map.setOnMapClickListener { point ->
                if (!disposed) channel.invokeMethod("mapTap", mapOf(
                    "latitude" to point.latitude, "longitude" to point.longitude))
            }
            view.map.setOnMarkerClickListener { marker ->
                if (!disposed) markers.idFor(marker)?.let { channel.invokeMethod("markerTap", it) }
                true
            }
            view.map.setMinZoomLevel(3f)
            view.map.setMaxZoomLevel(20f)
            view.map.setOnCameraChangeListener(object : AMap.OnCameraChangeListener {
                override fun onCameraChange(position: CameraPosition) { if (!disposed) channel.invokeMethod("cameraMove", cameraData(position)) }
                override fun onCameraChangeFinish(position: CameraPosition) { if (!disposed) channel.invokeMethod("cameraIdle", cameraData(position)) }
            })
            view.map.setOnMapTouchListener { event ->
                if (!disposed) {
                    handleCameraTouch(view.map, event)
                    zoomTapDetector.onTouchEvent(event)
                }
            }
            view.map.setOnMapLoadedListener { update("loaded") }
            view.map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(lat, lng), zoom))
            update("ready")
        } catch (_: Exception) { update("failed") }
    }
    private fun setOptions(map: AMap, args: Map<*, *>) {
        val mapType = when (args["mapType"]) {
            "standard" -> AMap.MAP_TYPE_NORMAL
            "satellite" -> AMap.MAP_TYPE_SATELLITE
            else -> throw IllegalArgumentException()
        }
        fun flag(key: String) = args[key] as? Boolean ?: throw IllegalArgumentException()
        val scroll = flag("scrollEnabled")
        val zoom = flag("zoomEnabled")
        val rotate = flag("rotateEnabled")
        val tilt = flag("tiltEnabled")
        val inertia = flag("inertiaEnabled")
        val compass = flag("compassEnabled")
        val scale = flag("scaleEnabled")
        val zoomControls = flag("zoomControlsEnabled")
        val buildings = (args["buildingsEnabled"] ?: true) as? Boolean ?: throw IllegalArgumentException()
        val min = ((args["minZoom"] ?: 3.0) as? Number)?.toDouble()
        val max = ((args["maxZoom"] ?: 20.0) as? Number)?.toDouble()
        require(min != null && max != null && min in 3.0..20.0 && max in min..20.0)
        val oldType = map.mapType
        val oldMin = map.minZoomLevel
        val oldMax = map.maxZoomLevel
        cameraEvidence("reset")
        if (oldType != mapType) map.mapType = mapType
        writeZoomRange(map, min.toFloat(), max.toFloat())
        val actualMin = map.minZoomLevel
        val actualMax = map.maxZoomLevel
        if (!(actualMin >= min.toFloat() && actualMax <= max.toFloat() && actualMin <= actualMax)) {
            if (oldType != mapType) map.mapType = oldType
            writeZoomRange(map, oldMin, oldMax)
            throw UnsupportedOperationException()
        }
        map.uiSettings.apply {
            isScrollGesturesEnabled = scroll && inertia
            isZoomGesturesEnabled = zoom
            isRotateGesturesEnabled = rotate
            isTiltGesturesEnabled = tilt
            isCompassEnabled = compass
            isScaleControlsEnabled = scale
            isZoomControlsEnabled = zoomControls
        }
        trackingDrag = false
        directDragEnabled = scroll && !inertia
        if (directDragEnabled) map.stopAnimation()
        map.showBuildings(buildings)
        val current = map.cameraPosition.zoom
        val bounded = current.coerceIn(actualMin, actualMax)
        if (current != bounded) {
            cameraEvidence("program")
            map.moveCamera(CameraUpdateFactory.zoomTo(bounded))
        }
    }

    private fun writeZoomRange(map: AMap, min: Float, max: Float) {
        // Widen first so a disjoint new interval is not clipped against the old one.
        if (min < map.minZoomLevel) map.setMinZoomLevel(min)
        if (max != map.maxZoomLevel) map.setMaxZoomLevel(max)
        if (min != map.minZoomLevel) map.setMinZoomLevel(min)
    }

    private fun handleCameraTouch(map: AMap, event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                dragX = event.x
                dragY = event.y
                trackingDrag = true
                dragging = false
                cameraEvidence("start", map.cameraPosition)
                if (directDragEnabled) map.stopAnimation()
            }
            MotionEvent.ACTION_MOVE -> {
                if (!trackingDrag || event.pointerCount != 1) return
                val dx = event.x - dragX
                val dy = event.y - dragY
                if (!dragging && dx * dx + dy * dy < touchSlop.toFloat() * touchSlop) return
                if (!dragging) cameraEvidence("drag")
                dragging = true
                dragX = event.x
                dragY = event.y
                if (directDragEnabled && (dx != 0f || dy != 0f)) map.moveCamera(CameraUpdateFactory.scrollBy(-dx, -dy))
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                trackingDrag = false
                cameraEvidence("multi")
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                trackingDrag = false
                cameraEvidence(if (event.actionMasked == MotionEvent.ACTION_UP) "end" else "cancel")
            }
        }
    }

    private fun fitBounds(view: MapView, args: Map<*, *>) {
        fun number(key: String): Double {
            val value = (args[key] as? Number)?.toDouble() ?: throw IllegalArgumentException()
            require(value.isFinite())
            return value
        }
        val south = number("south")
        val north = number("north")
        val west = number("west")
        val east = number("east")
        require(south >= -85.05112878 && north <= 85.05112878 && south < north &&
            west >= -180 && east <= 180 && west < east && east - west <= 180)
        val density = view.resources.displayMetrics.density
        fun pixels(edge: String): Double {
            val value = number(edge)
            require(value >= 0)
            return kotlin.math.ceil(value * density)
        }
        val left = pixels("left")
        val right = pixels("right")
        val top = pixels("top")
        val bottom = pixels("bottom")
        require(left + right < view.width && top + bottom < view.height)
        val animated = args["animated"] as? Boolean ?: throw IllegalArgumentException()
        val bounds = LatLngBounds(LatLng(south, west), LatLng(north, east))
        val update = CameraUpdateFactory.newLatLngBoundsRect(
            bounds, left.toInt(), right.toInt(), top.toInt(), bottom.toInt())
        cameraEvidence("program")
        setScreenAnchor(view, null)
        if (animated) view.map.animateCamera(update) else view.map.moveCamera(update)
    }

    private fun setScreenAnchor(view: MapView, anchor: Point?) {
        if (anchor != null) {
            view.map.setPointToCenter(anchor.x, anchor.y)
            screenAnchorMode = ScreenAnchorMode.CUSTOM
        } else if (screenAnchorMode != ScreenAnchorMode.SDK_DEFAULT) {
            // The SDK retains the supplied pixels even when they are the current center.
            view.map.setPointToCenter(view.width / 2, view.height / 2)
            screenAnchorMode = ScreenAnchorMode.CENTERED
        }
    }

    private fun updatePolylines(map: AMap, args: Map<*, *>) {
        val upsert = args["upsert"] as? List<*> ?: throw IllegalArgumentException()
        val remove = (args["remove"] as? List<*>)?.map {
            it as? String ?: throw IllegalArgumentException()
        } ?: throw IllegalArgumentException()
        val options = mutableMapOf<String, PolylineOptions>()
        for (item in upsert) {
            val line = item as? Map<*, *> ?: throw IllegalArgumentException()
            val id = line["id"] as? String ?: throw IllegalArgumentException()
            val width = (line["width"] as? Number)?.toDouble() ?: throw IllegalArgumentException()
            val color = line["color"] as? Int ?: throw IllegalArgumentException()
            val points = line["points"] as? List<*> ?: throw IllegalArgumentException()
            require(id.isNotEmpty() && id !in options && id !in remove && width in 1.0..128.0 && points.size >= 2)
            options[id] = PolylineOptions().addAll(decodePoints(points))
                .width(width.toFloat() * container.resources.displayMetrics.density).color(color)
        }
        val staged = mutableMapOf<String, Polyline>()
        try {
            for ((id, option) in options) {
                staged[id] = map.addPolyline(option) ?: error("Polyline creation failed")
            }
        } catch (error: Exception) {
            staged.values.forEach { it.remove() }
            throw error
        }
        for ((id, line) in staged) {
            polylines[id]?.remove()
            polylines[id] = line
        }
        remove.forEach { id ->
            polylines[id]?.remove()
            polylines.remove(id)
        }
    }

    private fun decodePoints(points: List<*>) = points.map {
        val point = it as? List<*> ?: throw IllegalArgumentException()
        require(point.size == 2)
        val lat = (point[0] as? Number)?.toDouble() ?: throw IllegalArgumentException()
        val lng = (point[1] as? Number)?.toDouble() ?: throw IllegalArgumentException()
        require(lat in -90.0..90.0 && lng in -180.0..180.0)
        LatLng(lat, lng)
    }

    private fun updatePolygons(map: AMap, args: Map<*, *>) {
        val upsert = args["upsert"] as? List<*> ?: throw IllegalArgumentException()
        val remove = (args["remove"] as? List<*>)?.map { it as? String ?: throw IllegalArgumentException() }
            ?: throw IllegalArgumentException()
        val options = mutableMapOf<String, PolygonOptions>()
        for (item in upsert) {
            val shape = item as? Map<*, *> ?: throw IllegalArgumentException()
            val id = shape["id"] as? String ?: throw IllegalArgumentException()
            val points = decodePoints(shape["points"] as? List<*> ?: throw IllegalArgumentException())
            val width = (shape["strokeWidth"] as? Number)?.toDouble() ?: throw IllegalArgumentException()
            val fill = shape["fillColor"] as? Int ?: throw IllegalArgumentException()
            val stroke = shape["strokeColor"] as? Int ?: throw IllegalArgumentException()
            require(id.isNotEmpty() && id !in options && id !in remove && width in 1.0..128.0 &&
                points.toSet().size >= 3)
            options[id] = PolygonOptions().addAll(points).fillColor(fill).strokeColor(stroke)
                .strokeWidth(width.toFloat() * container.resources.displayMetrics.density)
        }
        for ((id, option) in options) {
            val shape = polygons[id]
            if (shape == null) {
                polygons[id] = map.addPolygon(option) ?: error("Polygon creation failed")
            } else {
                shape.points = option.points
                shape.fillColor = option.fillColor
                shape.strokeColor = option.strokeColor
                shape.strokeWidth = option.strokeWidth
            }
        }
        for (id in remove) {
            polygons[id]?.remove()
            polygons.remove(id)
        }
    }

    private fun updateCircles(map: AMap, args: Map<*, *>) {
        val upsert = args["upsert"] as? List<*> ?: throw IllegalArgumentException()
        val remove = (args["remove"] as? List<*>)?.map {
            it as? String ?: throw IllegalArgumentException()
        } ?: throw IllegalArgumentException()
        val options = mutableMapOf<String, CircleOptions>()
        for (item in upsert) {
            val circle = item as? Map<*, *> ?: throw IllegalArgumentException()
            val id = circle["id"] as? String ?: throw IllegalArgumentException()
            val latitude = (circle["latitude"] as? Number)?.toDouble() ?: throw IllegalArgumentException()
            val longitude = (circle["longitude"] as? Number)?.toDouble() ?: throw IllegalArgumentException()
            val radius = (circle["radiusMeters"] as? Number)?.toDouble() ?: throw IllegalArgumentException()
            val width = (circle["strokeWidth"] as? Number)?.toDouble() ?: throw IllegalArgumentException()
            val fill = circle["fillColor"] as? Int ?: throw IllegalArgumentException()
            val stroke = circle["strokeColor"] as? Int ?: throw IllegalArgumentException()
            require(id.isNotEmpty() && id !in options && id !in remove &&
                latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
                radius.isFinite() && radius > 0 && width in 1.0..128.0)
            options[id] = CircleOptions().center(LatLng(latitude, longitude)).radius(radius)
                .fillColor(fill).strokeColor(stroke)
                .strokeWidth(width.toFloat() * container.resources.displayMetrics.density)
        }
        val staged = mutableMapOf<String, Circle>()
        try {
            for ((id, option) in options) {
                staged[id] = map.addCircle(option) ?: error("Circle creation failed")
            }
        } catch (error: Exception) {
            staged.values.forEach { it.remove() }
            throw error
        }
        for ((id, circle) in staged) {
            circles[id]?.remove()
            circles[id] = circle
        }
        remove.forEach { id ->
            circles[id]?.remove()
            circles.remove(id)
        }
    }

    private fun cameraData(position: CameraPosition): Map<String, Any> = mapOf(
        "latitude" to position.target.latitude, "longitude" to position.target.longitude,
        "zoom" to position.zoom.toDouble(), "bearing" to position.bearing.toDouble(),
        "tilt" to position.tilt.toDouble())

    private fun cameraEvidence(kind: String, position: CameraPosition? = null) {
        channel.invokeMethod("cameraEvidence", (position?.let(::cameraData) ?: emptyMap()) + ("kind" to kind))
    }
    private fun update(value: String) {
        if (disposed || (status == "loaded" && value == "ready")) return
        status = value
        channel.invokeMethod("status", value)
    }
    fun resume() { if (!disposed && !resumed) { mapView?.onResume(); resumed = true } }
    fun pause() { if (!disposed && resumed) { mapView?.onPause(); resumed = false } }
    override fun getView(): View = container
    override fun dispose() {
        if (disposed) return
        pause()
        disposed = true
        mapView?.map?.setOnMapTouchListener(null)
        mapView?.map?.setOnMapClickListener(null)
        mapView?.map?.setOnMarkerClickListener(null)
        markers.clear()
        polylines.values.forEach { it.remove() }
        polylines.clear()
        polygons.values.forEach { it.remove() }
        polygons.clear()
        circles.values.forEach { it.remove() }
        circles.clear()
        mapView?.map?.setOnCameraChangeListener(null)
        mapView?.map?.setOnMapLoadedListener(null)
        mapView?.onDestroy()
        mapView = null
        container.removeAllViews()
        channel.setMethodCallHandler(null)
        onDisposed(this)
    }
}
