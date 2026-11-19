# flutter_amap_map

Display native AMap maps in Flutter on **Android, iOS and HarmonyOS NEXT**. The plugin includes camera controls, overlays, coordinate projection, place search and geocoding. All geographic coordinates use **GCJ-02**, in latitude, longitude order. The only Dart runtime dependency is Flutter.

中文用户可直接阅读本页的中文接入小节。完整中文版在包内的 `doc/README.zh-CN.md`。

## Install

Version 0.0.1 is available as source. Clone this repository or extract the source archive into a `flutter_amap_map` directory next to your application, add the following dependency to the application's `pubspec.yaml`, then run `flutter pub get`.

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_amap_map:
    path: ../flutter_amap_map
```

Obtain a separate AMap key for each platform and bind it to your application's identity. Keep keys and signing files in your local configuration.

| Platform | Host setup |
| --- | --- |
| Android | Standard Flutter, minSdk 24, compileSdk 36, Java 17. Bind the key to the application ID and signing certificate SHA-1. |
| iOS | Standard Flutter with CocoaPods and static frameworks. Add the podspec source below to the Runner target. With Xcode 27.2 use an iOS 15 or newer deployment target in both Runner and the Podfile. Bind the key to the bundle ID. |
| HarmonyOS NEXT | Use the OHOS Flutter SDK (tested with 3.41.9). Call `registerAMapHarmonyView()` from the dedicated Harmony Dart entry point. Use a transparent TEXTURE FlutterPage as shown in the example. |

In the iOS Runner target, place this line after `flutter_install_all_ios_pods`. It resolves the pinned map SDK from the official archive and verifies its SHA-256.

```ruby
pod 'AMap3DMap', :podspec => '.symlinks/plugins/flutter_amap_map/ios/sdk/AMap3DMap.podspec.json'
```

For Harmony, keep the platform-specific import in its own entry point (as in `example/lib/main_harmony.dart`). The example ArkUI page sets `xComponentType: XComponentType.TEXTURE` and `xComponentColor: Color.Transparent`.

```dart
import 'package:flutter_amap_map/flutter_amap_map_harmony.dart';
import 'main.dart' as app;

void main() {
  registerAMapHarmonyView();
  app.main();
}
```

## Display a map

Show the applicable AMap privacy notice and obtain the user's consent before initializing the SDK. Once initialization completes, place the returned widget in a view with a finite width and height.

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

## API and examples

| Capability | What the host can do |
| --- | --- |
| Camera and map options | Move or read the camera, fit bounds with padding, set zoom limits, switch standard/satellite maps, configure gestures and controls. |
| Overlays | Supply PNG markers, polylines, circles in meters and polygons. Reuse an ID to update an overlay, or remove it from the list to delete it. |
| Interaction and projection | Handle map and marker taps, distinguish camera gesture and programmatic events, convert GCJ-02 positions to and from map-local Flutter logical pixels. |
| Places and addresses | Query input suggestions, search by keyword or nearby coordinates, paginate, look up a place by ID, geocode an address or reverse geocode a coordinate. |

Each map owns its controller. Use `onMapCreated` to obtain it and `onCameraIdle` to read the settled position. Search is also available after SDK initialization in applications that do not display a map. The package includes an interactive example with simulated tracks, editable fences and map labels.

## Compatibility and verification

All three platforms have rendered a basic map on a physical device. Recent place search, geocoding and point-selection interactions have Android device coverage. The corresponding iOS and HarmonyOS changes have build coverage. The recorded lifecycle runs were bounded. Long-running and cross-device stability testing remains open.

The iOS integration uses CocoaPods. The pinned AMapFoundation lacks the arm64 simulator slice required by Apple Silicon iOS 26+ simulators. On HarmonyOS, native DISPLAY composition supports rectangular maps, with limits on opacity, clipping and transitions.

## 中文接入

插件使用 GCJ-02 坐标，依次传入纬度、经度。取得用户隐私同意后调用 `AMapSdk.initialize`，再在有宽高的容器内创建 `AMapView`。Android 和 iOS 使用标准 Flutter，HarmonyOS NEXT 使用 OHOS Flutter 和独立入口。地点及地址查询可以独立使用。示例提供轨迹、围栏、悬浮标签和选点页面。

The following files ship in the source archive.

| File | Contents |
| --- | --- |
| `doc/README.zh-CN.md` | 完整中文指南与可点击的本地文档导航 |
| `doc/platforms.md` | Platform configuration, pinned SDK versions and rendering limits |
| `doc/api.md` | Camera, overlays, projection, search and error handling |
| `example/README.md` | Commands for running the example with your platform key |
| `example/ios/Podfile` | Complete CocoaPods configuration |
| `LICENSE` and `THIRD_PARTY_NOTICES.md` | License text and third-party dependencies |

## License

The plugin code and original example marker artwork are MIT licensed. AMap SDKs, services and map data are subject to AMap's own terms. [AMap developer terms](https://lbs.amap.com/pages/terms/) · [AMap privacy policy](https://lbs.amap.com/pages/privacy/)
