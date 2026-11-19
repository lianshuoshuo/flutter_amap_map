package dev.hscw.amap_flutter_bridge

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.security.MessageDigest
import com.amap.api.maps.AMap
import com.amap.api.maps.model.BitmapDescriptor
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions

internal class MarkerStore(private val density: Float) {
    private data class Entry(val marker: Marker, val icon: BitmapDescriptor, val imageKey: String)
    private val entries = mutableMapOf<String, Entry>()
    fun idFor(marker: Marker): String? = entries.entries.firstOrNull { it.value.marker.id == marker.id }?.key
    fun apply(map: AMap, args: Map<*, *>) {
        val upsert = args["upsert"] as? List<*> ?: throw IllegalArgumentException()
        val remove = (args["remove"] as? List<*>)?.map { it as? String ?: throw IllegalArgumentException() }
            ?: throw IllegalArgumentException()
        val prepared = mutableMapOf<String, Pair<MarkerOptions, BitmapDescriptor>>()
        val staged = mutableMapOf<String, Entry>()
        val imageKeys = mutableMapOf<String, String>()
        try {
            upsert.forEach { value ->
                val data = value as? Map<*, *> ?: throw IllegalArgumentException()
                val id = data["id"] as? String ?: throw IllegalArgumentException()
                require(id.isNotEmpty() && !prepared.containsKey(id) && !remove.contains(id))
                fun number(key: String, min: Double, max: Double): Double {
                    val n = (data[key] as? Number)?.toDouble() ?: throw IllegalArgumentException()
                    require(n.isFinite() && n in min..max)
                    return n
                }
                val lat = number("latitude", -90.0, 90.0)
                val lng = number("longitude", -180.0, 180.0)
                val width = number("width", 0.000001, 512.0)
                val height = number("height", 0.000001, 512.0)
                val u = number("anchorU", 0.0, 1.0)
                val v = number("anchorV", 0.0, 1.0)
                val rotation = number("rotation", 0.0, 360.0)
                val z = number("zIndex", -1000000.0, 1000000.0)
                require(z % 1.0 == 0.0 && rotation < 360.0)
                val visible = data["visible"] as? Boolean ?: throw IllegalArgumentException()
                val bytes = data["pngBytes"] as? ByteArray ?: throw IllegalArgumentException()
                require(bytes.size in 8..4194304 && bytes.take(8) == listOf(137,80,78,71,13,10,26,10).map { it.toByte() })
                val imageKey = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) } + "/$width/$height"
                imageKeys[id] = imageKey
                val existing = entries[id]
                val icon = if (existing?.imageKey == imageKey) existing.icon else {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    require(bounds.outWidth in 1..4096 && bounds.outHeight in 1..4096)
                    val original = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: throw IllegalArgumentException()
                    val bitmap = Bitmap.createScaledBitmap(original, (width * density).toInt().coerceAtLeast(1),
                        (height * density).toInt().coerceAtLeast(1), true)
                    val descriptor = BitmapDescriptorFactory.fromBitmap(bitmap)
                    if (bitmap !== original) original.recycle()
                    descriptor
                }
                prepared[id] = Pair(MarkerOptions().position(LatLng(lat, lng)).icon(icon)
                    .anchor(u.toFloat(), v.toFloat()).rotateAngle((-rotation).toFloat())
                    .zIndex(z.toFloat()).visible(visible), icon)
            }
            // All images/parameters are validated before changing the map.
            prepared.forEach { (id, item) ->
                val marker = map.addMarker(item.first) ?: throw IllegalStateException()
                staged[id] = Entry(marker, item.second, imageKeys[id]!!)
            }
            staged.forEach { (id, entry) ->
                entries.remove(id)?.let { it.marker.remove(); if (it.icon !== entry.icon) it.icon.recycle() }
                entries[id] = entry
            }
            remove.forEach { id -> entries.remove(id)?.let { it.marker.remove(); it.icon.recycle() } }
        } catch (error: Exception) {
            staged.forEach { (id, entry) -> if (entries[id] !== entry) entry.marker.remove() }
            prepared.values.forEach { item -> if (entries.values.none { it.icon === item.second }) item.second.recycle() }
            throw error
        }
    }
    fun clear() {
        entries.values.forEach { it.marker.remove(); it.icon.recycle() }
        entries.clear()
    }
}
