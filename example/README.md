# 运行高德地图示例

在示例首页阅读高德隐私说明，勾选同意并初始化，然后从菜单选择要体验的功能。足迹和定位器使用公开地点的 GCJ-02 坐标与模拟时间。地点搜索和地址查询会访问真实的高德服务。

1. 为要运行的平台申请自己的应用 Key，将其绑定到示例的应用标识。Android 还需绑定实际签名指纹，iOS 真机和 HarmonyOS 真机还需配置自己的调试签名。[平台说明](../doc/platforms.md)
2. 从源码仓库运行时，在仓库忽略的 `config/` 下保存对应的 `android.json`、`ios.json` 或 `harmony.json`。从发行包运行时，把文件放在源码树外的本地私有目录，并将下方路径换成它的绝对路径。文件格式为 `{"AMAP_API_KEY":"YOUR_PLATFORM_KEY"}`。
3. 进入本目录，使用相应的 Flutter SDK 执行命令。将设备参数替换为本机 `flutter devices` 列出的标识。

```sh
# Android 或 iOS，使用标准 Flutter
flutter pub get
flutter run -d <android-device> --dart-define-from-file=../config/android.json
flutter run -d <ios-device> --dart-define-from-file=../config/ios.json
```

```sh
# HarmonyOS NEXT，在另一个干净副本中使用 OHOS Flutter
flutter pub get
flutter run -d <harmony-device> --target lib/main_harmony.dart --dart-define-from-file=../config/harmony.json
```

| 菜单 | 可以试什么 |
| --- | --- |
| 足迹、定位器地图 | 切换日期，点击轨迹点查看时间地址，观察标记和 Flutter 标签同步移动，拖图后回中 |
| 位置校准、围栏选点 | 拖动取点或点选地点和门牌号，查看选点地址和米制围栏 |
| 不规则围栏 | 拖动顶点，缩放或平移后检查顶点手柄，切换样式和删除 |
| POI 搜索 | 输入提示、关键词及周边分页、地点详情和地址查坐标 |
| 查找宠物投影、地图设置、地图调试 | 标签投影、底图与控件、相机和不同地图实例的覆盖物 |

主入口和场景均在本示例内。运行 `flutter test` 可验证菜单、数据和界面联动。真实瓦片与在线服务需用自己应用的 Key 在设备上验证。[公共 API](../doc/api.md)
