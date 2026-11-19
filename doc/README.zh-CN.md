# flutter_amap_map

[English](../README.md)

Flutter 高德地图插件，支持 Android、iOS 和 HarmonyOS NEXT。可显示原生地图、更新覆盖物、控制相机，也可以单独搜索地点或查询地址。经纬度统一为 **GCJ-02**，参数顺序为纬度、经度。Dart 运行时依赖只有 Flutter SDK。

## 安装

当前可使用 `0.0.1` 源码。将此仓库克隆或将源码包解压到应用旁边的 `flutter_amap_map` 目录，在应用的 `pubspec.yaml` 中添加依赖，然后运行 `flutter pub get`。

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_amap_map:
    path: ../flutter_amap_map
```

| 平台 | 接入方式 |
| --- | --- |
| Android | 标准 Flutter，Android API 24 及以上。插件使用 Java 17，编译 SDK 36。 |
| iOS | 标准 Flutter + CocoaPods。宿主的 Podfile 需声明包内地图 SDK 的 podspec 来源。插件声明 iOS 13 起，示例使用 iOS 15 部署目标。 |
| HarmonyOS NEXT | 使用 OHOS Flutter SDK、专用 Dart 入口和透明 TEXTURE 宿主。已验证构建的工具链为 OHOS Flutter 3.41.9。 |

Android、iOS 使用各自的应用 Key。HarmonyOS 使用绑定到其应用的 Key。各端固定 SDK 版本、Podfile 完整片段、Harmony 宿主配置和现有渲染限制见[平台接入](platforms.md)。

## 显示地图

宿主展示高德隐私说明，取得用户同意后再初始化。以下函数可在同意按钮的回调中调用，将返回的地图放入有宽高的页面。请求失败时由调用方显示错误。运行完整示例见[示例说明](../example/README.md)。

```dart
import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/widgets.dart';

Future<Widget> createMap({
  required String platformKey,
  required bool privacyAgreed,
}) async {
  await AMapSdk.initialize(apiKey: platformKey, privacyAgreed: privacyAgreed);
  return AMapView(
    latitude: 22.5431,
    longitude: 114.0579,
    zoom: 16,
    onStatusChanged: (status) => debugPrint('Map: ${status.name}'),
    onError: (code) => debugPrint('Map error: $code'),
  );
}
```

## 已提供的功能

| 功能 | 主要接口 |
| --- | --- |
| 相机与底图 | `moveCamera`、`getCamera`、`fitBounds`，标准／卫星地图，缩放范围、手势和控件 |
| 覆盖物 | PNG 标记、折线、米制圆形和多边形。相同 ID 更新，从集合移除即删除 |
| 交互与投影 | 地图与标记点击、相机移动及结束事件、地图内 Flutter 逻辑像素与 GCJ-02 坐标双向投影 |
| 地点与地址 | 输入提示、关键词和周边分页搜索、按 ID 查详情、地址查坐标及坐标查地址 |

`onMapCreated` 提供当前地图的控制器。`AMapStatus.loaded` 反映 SDK 的加载信号。地点查询可在初始化后单独运行，无需创建地图或申请手机定位权限。各接口的单位、结果为空和出错时的处理见[公共 API 用法](api.md)。

## 验证范围

三端均有基础地图真机出图记录。近期的搜索、地址与选点联动在 Android 真机验证，iOS 和 HarmonyOS 这些增量功能验证到构建。生命周期已有有界短测，长时间运行和跨设备兼容仍待验证。

## 许可证

插件自有源码和自绘示例图标采用 MIT。使用高德服务、SDK 和地图数据须遵守高德对应条款。[MIT 许可证](../LICENSE) · [第三方说明](../THIRD_PARTY_NOTICES.md)
