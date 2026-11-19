# 平台接入

Dart SDK 要求 `^3.10.3`，Flutter 要求 `>=3.38.4`。标准 Flutter 构建 Android 和 iOS，HarmonyOS NEXT 使用 OHOS Flutter SDK。宿主自行取得用户同意并为每个平台配置应用 Key。[可运行示例](../example/README.md)

| 平台 | 固定的高德依赖 | Key 绑定 |
| --- | --- | --- |
| Android | `com.amap.api:3dmap-location-search:11.2.100_loc11.2.100_sea9.8.1` | 宿主包名与实际构建使用的签名证书 SHA-1 |
| iOS | Map `11.3.100`，Foundation `1.9.1`，Search `9.8.1` | 宿主 Bundle ID |
| HarmonyOS NEXT | map3d `11.1.104`，common、location、search `11.2.1` | 实际安装包的应用标识，按高德控制台设置 |

### Android

在 Android 工程使用 Google Maven 和 Maven Central。插件使用 Kotlin、Java 17，最低 API 为 24，compileSdk 为 36。库的 Manifest 声明网络访问与网络状态权限。当前插件使用 Kotlin Gradle Plugin，Flutter 3.44 的 AGP 9 应用模板会提示将来需迁移到内置 Kotlin。地图和搜索只消费传入的 GCJ-02 坐标。

### iOS

在 Xcode 27.2 中，请把 Runner（及测试 target）的 iOS Deployment Target 设为 15.0 或更高，并同步设置 Podfile 顶层的 `platform :ios, '15.0'`。该工具链要求应用最低系统为 iOS 15，空白模板可能仍默认 13。

使用 CocoaPods 和静态 framework。在宿主 `ios/Podfile` 的 Runner target 中，在 Flutter 安装 pods 的语句之后增加地图 SDK 来源。保留项目原有的 Flutter 安装和 post-install 逻辑。

```ruby
target 'Runner' do
  use_frameworks! :linkage => :static
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  pod 'AMap3DMap', :podspec => '.symlinks/plugins/flutter_amap_map/ios/sdk/AMap3DMap.podspec.json'
end
```

运行 `flutter pub get`，然后在 `ios/` 下执行 `pod install`。地图 podspec 指向高德官方 ZIP 并校验 SHA-256。Foundation 和 Search 通过 CocoaPods 索引解析。从旧版本迁移时，可对这三个 pod 更新锁定版本。插件的 podspec 声明 iOS 13，示例部署目标为 iOS 15。Flutter 3.44 在启用 Swift Package Manager 的宿主中会回退到 CocoaPods 并提示迁移。固定的 Foundation 缺少 Apple Silicon 的 iOS 26 及以上模拟器所需的 arm64 模拟器切片。

### HarmonyOS NEXT

在 OHOS 入口注册视图，再启动共享 Flutter 应用。示例位于 `example/lib/main_harmony.dart`。

```dart
import 'package:flutter_amap_map/flutter_amap_map_harmony.dart';
import 'main.dart' as app;

void main() {
  registerAMapHarmonyView();
  app.main();
}
```

在宿主 ArkUI 页面创建透明纹理的 FlutterPage，在工程 build-profile 中启用 `buildOption.strictMode.useNormalizedOHMUrl`。示例 entry 声明了 `ohos.permission.INTERNET` 和 `ohos.permission.GET_NETWORK_INFO`。

```ts
FlutterPage({
  viewId: this.viewId,
  xComponentType: XComponentType.TEXTURE,
  xComponentColor: Color.Transparent
})
```

当前采用原生 DISPLAY 节点显示矩形地图。Flutter 的 Opacity、FadeTransition 和通过 saveLayer 合成的半透明地图不受支持。复杂裁切、滚动隐藏、页面转场和图层叠加需在目标设备单独验证。地图库固定在 11.1.104，升级前应复测双地图、创建销毁和前后台切换。[示例 ArkUI 页面](../example/ohos/entry/src/main/ets/pages/Index.ets)

### 隐私和数据

隐私确认和 Key 均由宿主提供。拒绝同意时初始化报告 `privacy_not_agreed`。地图使用高德在线资源。搜索与地址请求会把查询需要的关键词、地点 ID、地址或坐标发送给高德。插件的本地配置方式和第三方依赖见[示例说明](../example/README.md)和[第三方说明](../THIRD_PARTY_NOTICES.md)。
