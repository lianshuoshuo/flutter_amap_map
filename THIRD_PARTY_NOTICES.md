# 第三方说明

本包的 Flutter 桥接代码、三端原生适配代码和示例自绘图标使用 MIT 许可证。分发这些文件时请保留版权和许可声明。[MIT 许可证](LICENSE)

## 高德开放平台

地图、地图数据、地点搜索和地址查询由高德 SDK 和服务提供。MIT 许可的范围仅限本项目自有作品。使用或分发含高德 SDK 的应用时，应按宿主用途核对高德的开发者服务协议、商业授权要求和隐私要求。宿主自行注册应用、配置各平台 Key 并取得用户同意。[高德开放平台服务协议](https://lbs.amap.com/pages/terms/) · [高德开放平台隐私权政策](https://lbs.amap.com/pages/privacy/)

| 平台 | 构建时获取的第三方组件 |
| --- | --- |
| Android | Maven Central 的 `com.amap.api:3dmap-location-search:11.2.100_loc11.2.100_sea9.8.1` |
| iOS | CocoaPods 获取 AMap3DMap 11.3.100、AMapFoundation 1.9.1、AMapSearch 9.8.1。随包提供的地图 podspec 记录官方 ZIP 地址和 SHA-256 |
| HarmonyOS NEXT | OHPM 获取 `@amap/amap_lbs_map3d` 11.1.104，以及 `@amap/amap_lbs_common`、`@amap/amap_lbs_location`、`@amap/amap_lbs_search` 11.2.1 |

插件源码包仅提供原生依赖声明。各平台的构建工具下载相应 SDK，权利归其各自权利人所有。[平台接入](doc/platforms.md)

## Flutter

构建和运行示例需要单独安装 Flutter SDK。Flutter 项目的源码采用 BSD 3-Clause，其包含的第三方组件分别适用对应许可。[Flutter 许可证](https://github.com/flutter/flutter/blob/master/LICENSE)
