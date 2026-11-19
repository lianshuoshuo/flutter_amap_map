import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:amap_example_scenes/locator_map_page.dart';
import 'package:amap_example_scenes/trace_demo_page.dart';

import 'calibration_demo.dart';
import 'map_settings_demo.dart';
import 'map_validation_page.dart';
import 'pet_label_demo.dart';
import 'poi_search_demo.dart';
import 'polygon_fence_demo.dart';

class DemoMenu extends StatefulWidget {
  const DemoMenu({super.key, required this.apiKey});

  final String apiKey;

  @override
  State<DemoMenu> createState() => _DemoMenuState();
}

class _DemoMenuState extends State<DemoMenu> {
  bool _consent = false;
  bool _busy = false;
  bool _initialized = false;
  String? _error;

  Future<void> _initialize() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AMapSdk.initialize(apiKey: widget.apiKey, privacyAgreed: _consent);
      if (mounted) setState(() => _initialized = true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _error = error is PlatformException ? error.code : '缺少 Key 或初始化失败',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _entry(String title, IconData icon, WidgetBuilder builder) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () =>
        Navigator.of(context).push<void>(MaterialPageRoute(builder: builder)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('高德地图示例')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: _initialized
            ? [
                _entry('足迹', Icons.timeline, (_) {
                  return const TraceDemoPage();
                }),
                _entry('定位器地图', Icons.pets_outlined, (_) {
                  return const _DemoPinPage(
                    title: '定位器地图',
                    builder: LocatorMapPage.new,
                  );
                }),
                _entry(
                  '位置校准',
                  Icons.my_location,
                  (_) => const CalibrationDemo(),
                ),
                _entry('围栏选点', Icons.circle_outlined, (_) {
                  return const CalibrationDemo(fence: true);
                }),
                _entry(
                  '不规则围栏',
                  Icons.pentagon_outlined,
                  (_) => const PolygonFenceDemo(),
                ),
                _entry('POI 搜索', Icons.search, (_) => const PoiSearchDemo()),
                _entry('查找宠物投影', Icons.pin_drop_outlined, (_) {
                  return const _DemoPinPage(
                    title: '查找宠物投影',
                    builder: PetLabelDemo.new,
                  );
                }),
                _entry(
                  '地图设置',
                  Icons.layers_outlined,
                  (_) => const MapSettingsDemo(),
                ),
                _entry('地图调试', Icons.tune, (_) => const MapValidationPage()),
              ]
            : [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SelectableText(
                    '本示例使用高德地图 SDK 加载地图，无需手机定位权限。'
                    '请先阅读高德隐私政策：\nhttps://lbs.amap.com/pages/privacy/',
                  ),
                ),
                CheckboxListTile(
                  value: _consent,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _consent = value ?? false),
                  title: const Text('已阅读并同意高德隐私政策'),
                ),
                FilledButton(
                  onPressed: _consent && !_busy ? _initialize : null,
                  child: const Text('初始化地图'),
                ),
                if (_error != null) Text(_error!),
              ],
      ),
    ),
  );
}

class _DemoPinPage extends StatefulWidget {
  const _DemoPinPage({required this.title, required this.builder});

  final String title;
  final Widget Function({required Uint8List markerPng}) builder;

  @override
  State<_DemoPinPage> createState() => _DemoPinPageState();
}

class _DemoPinPageState extends State<_DemoPinPage> {
  late final _pin = rootBundle.load(demoPetPinAsset);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _pin,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data != null) {
        return widget.builder(markerPng: Uint8List.sublistView(data));
      }
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: snapshot.hasError
              ? const Text('演示标记加载失败')
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
