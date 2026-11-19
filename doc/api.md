# 公共 API 用法

标准入口为 `package:flutter_amap_map/flutter_amap_map.dart`。地图与地点查询统一采用 GCJ-02，按纬度、经度顺序传值。以下代码在 `AMapSdk.initialize` 成功后使用。

## 相机和覆盖物

`AMapView` 的初始相机参数在创建时使用。从 `onMapCreated` 取得的控制器只属于该地图。移动命令完成表示 SDK 已接收，停止位置通过 `onCameraIdle` 取得。事件原因有 `userDrag`、`userZoom`、`programmatic` 和 `unknown`。

```dart
final camera = await controller.getCamera();
await controller.moveCamera(AMapCameraPosition(
  latitude: 22.54365,
  longitude: 114.05850,
  zoom: camera.zoom,
));
final offset = await controller.projectToScreen(
  const AMapLatLng(22.54365, 114.05850),
);
final coordinate = await controller.unprojectFromScreen(offset);
```

投影以地图左上角为原点，单位是 Flutter 逻辑像素。可以用 `fitBounds` 适配轨迹或围栏并设置四边留白。公共缩放范围为 3–20，具体设备可用的范围通过 `getZoomRange()` 读取。

```dart
AMapView(
  latitude: 22.5431,
  longitude: 114.0579,
  zoom: 16,
  circles: [
    AMapCircle(
      id: 'area',
      center: const AMapLatLng(22.5431, 114.0579),
      radiusMeters: 150,
    ),
  ],
);
```

创建新的覆盖物集合后重建 Widget。标记、折线、圆形和多边形使用稳定的 ID，圆半径以米计，线宽以逻辑像素计。标记接受 PNG 字节，`onMarkerTap` 返回被点中的 ID。资源随地图释放。

## 地点与地址

```dart
final places = await AMapPoiSearch.searchKeyword('深圳市民中心', city: '深圳');
final id = places.isEmpty ? null : places.first.id;
final detail = id == null ? null : await AMapPoiSearch.getById(id);
final candidates = await AMapGeocoder.forwardGeocode('福中三路2010号', city: '深圳');
if (candidates.isNotEmpty) {
  final address = await AMapGeocoder.reverseGeocode(candidates.first.coordinate);
  debugPrint(address.formattedAddress);
}
```

`inputTips` 允许只有文字的建议。`searchKeyword` 和 `searchNearby` 支持分页，`getById` 在高德明确没有该地点时返回 `null`。正向查询返回有坐标的候选并保留服务给出的匹配级别。逆向结果包括格式化地址、行政区和可用的 POI／AOI。无匹配候选时的空列表和服务失败分别反馈。

## 常见错误

Dart 参数校验会抛出 `ArgumentError` 或 `RangeError`。原生错误可从 `PlatformException.code` 读取，地点和地址服务可在 `details` 中附上高德数字错误码。

| 错误码 | 调用方如何处理 |
| --- | --- |
| `privacy_not_agreed`、`sdk_not_initialized` | 在宿主取得同意并成功初始化后再使用服务 |
| `map_not_ready`、`map_disposed` | 等待该地图就绪，退出页面后释放对旧控制器的引用 |
| `unsupported_option`、`unsupported_feature` | 根据平台和 SDK 支持情况调整操作。例如 iOS 没有原生缩放按钮 |
| `geocode_timeout`、`poi_search_timeout`、`operation_timeout` | 提示请求超时，允许用户重试 |
| `geocode_failed`、`poi_search_failed` | 显示服务错误，有高德错误码时可一并显示 |

[平台配置](platforms.md) · [交互示例](../example/README.md)
