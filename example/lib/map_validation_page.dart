import 'dart:ui' as ui;

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MapValidationPage extends StatefulWidget {
  const MapValidationPage({super.key});
  @override
  State<MapValidationPage> createState() => _MapValidationPageState();
}

class _MapValidationPageState extends State<MapValidationPage> {
  final _controllers = <int, AMapController>{};
  int _selected = 0;
  Uint8List? _markerPng;
  final _markers = <int, List<AMapMarker>>{};
  bool _shiftMarker = false;

  final _circles = <int, AMapCircle>{};

  void _updateCircle({bool fit = false}) {
    final index = _selected;
    final updated = _circles[index]?.radiusMeters == 300;
    setState(() {
      if (fit && _circles.containsKey(index)) return;
      _circles[index] = AMapCircle(
        id: 'area',
        center: updated
            ? const AMapLatLng(22.548, 114.065)
            : const AMapLatLng(22.5431, 114.0579),
        radiusMeters: updated ? 650 : 300,
        fillColor: updated ? const Color(0x66EF6C00) : const Color(0x551565C0),
        strokeColor: updated
            ? const Color(0xFFD84315)
            : const Color(0xFF1565C0),
        strokeWidth: updated ? 7 : 3,
      );
    });
    if (fit) {
      final circle = _circles[index]!;
      _fit(index, AMapBounds.fromCircle(circle), circle.strokeWidth);
    } else {
      _camera(false);
    }
  }

  final _polylines = <int, AMapPolyline>{};

  void _updatePolyline({bool fit = false}) {
    final index = _selected;
    final updated = _polylines[index]?.width == 6;
    setState(() {
      if (fit && _polylines.containsKey(index)) return;
      _polylines[index] = AMapPolyline(
        id: 'route',
        points: [
          const AMapLatLng(22.538, 114.050),
          updated
              ? const AMapLatLng(22.542, 114.058)
              : const AMapLatLng(22.550, 114.056),
          const AMapLatLng(22.545, 114.067),
        ],
        color: updated ? Colors.deepPurple : Colors.blue,
        width: updated ? 10 : 6,
      );
    });
    if (fit) {
      final line = _polylines[index]!;
      _fit(index, AMapBounds.fromPoints(line.points), line.width);
    } else {
      _camera(false);
    }
  }

  Future<void> _fit(int index, AMapBounds bounds, double strokeWidth) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final controller = _controllers[index];
    if (controller == null || controller.isDisposed) return;
    try {
      await controller.fitBounds(
        bounds,
        padding:
            const EdgeInsets.fromLTRB(40, 36, 28, 100) +
            EdgeInsets.all(strokeWidth / 2 + 2),
        animated: true,
      );
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = '地图 $index：${error.code}');
    }
  }

  @override
  void initState() {
    super.initState();
    _createMarkerImage();
  }

  Future<void> _createMarkerImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final path = Path()
      ..moveTo(18, 0)
      ..lineTo(36, 36)
      ..lineTo(18, 48)
      ..lineTo(0, 36)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.red);
    canvas.drawCircle(const Offset(18, 25), 7, Paint()..color = Colors.white);
    final picture = recorder.endRecording();
    final image = await picture.toImage(36, 48);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (mounted && bytes != null) {
      setState(() => _markerPng = bytes.buffer.asUint8List());
    }
  }

  void _updateMarker() {
    final png = _markerPng;
    if (png == null) return;
    _shiftMarker = !_shiftMarker;
    final selected = _selected;
    setState(
      () => _markers[selected] = [
        AMapMarker(
          id: 'sample',
          latitude: _shiftMarker ? 22.5431 : 22.5481,
          longitude: 114.0579,
          pngBytes: png,
          width: _shiftMarker ? 36 : 48,
          height: _shiftMarker ? 48 : 64,
          rotation: _shiftMarker ? 0 : 45,
        ),
      ],
    );
    _camera(false);
  }

  void _toggleMarkerVisibility() {
    final current = _markers[_selected];
    if (current == null || current.isEmpty) return;
    final m = current.first;
    setState(
      () => _markers[_selected] = [
        AMapMarker(
          id: m.id,
          latitude: m.latitude,
          longitude: m.longitude,
          pngBytes: m.pngBytes,
          width: m.width,
          height: m.height,
          anchorU: m.anchorU,
          anchorV: m.anchorV,
          rotation: m.rotation,
          zIndex: m.zIndex,
          visible: !m.visible,
        ),
      ],
    );
  }

  void _invalidMarkerImage() {
    setState(
      () => _markers[_selected] = [
        AMapMarker(
          id: 'sample',
          latitude: 22.5431,
          longitude: 114.0579,
          pngBytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]),
        ),
      ],
    );
  }

  bool _show = true;
  bool _two = false;
  int _generation = 0;
  String _message = '等待地图加载。';

  Future<void> _camera(bool animated) async {
    final selected = _selected;
    final controller = _controllers[selected];
    if (controller == null || controller.isDisposed) return;
    try {
      await controller.moveCamera(
        AMapCameraPosition(latitude: 22.5431, longitude: 114.0579, zoom: 14),
        animated: animated,
      );
      final camera = await controller.getCamera();
      if (mounted) {
        setState(
          () => _message =
              '地图 $selected 命令已接受；快照 ${camera.latitude}, ${camera.longitude}, ${camera.zoom}；动画完成看 idle',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.code);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('地图调试')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(_message)),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() => _show = !_show),
                child: Text(_show ? '销毁地图' : '创建地图'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _two = !_two;
                  if (!_two) _selected = 0;
                }),
                child: Text(_two ? '单地图' : '双地图'),
              ),
              TextButton(
                onPressed: () => setState(() => _generation++),
                child: const Text('重建'),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _selected = _selected == 0 && _two ? 1 : 0),
                child: Text('操作地图 $_selected'),
              ),
              TextButton(
                onPressed: () => _camera(false),
                child: const Text('移动深圳'),
              ),
              TextButton(
                onPressed: () => _camera(true),
                child: const Text('动画深圳'),
              ),
              TextButton(
                onPressed: _markerPng == null ? null : _updateMarker,
                child: const Text('添加/更新标记'),
              ),
              TextButton(
                onPressed: () => setState(() => _markers[_selected] = []),
                child: const Text('删除标记'),
              ),
              TextButton(
                onPressed: _toggleMarkerVisibility,
                child: const Text('隐藏/显示标记'),
              ),
              TextButton(
                onPressed: _invalidMarkerImage,
                child: const Text('测试无效PNG'),
              ),
              TextButton(
                onPressed: _updatePolyline,
                child: const Text('添加/更新折线'),
              ),
              TextButton(
                onPressed: () => setState(() => _polylines.remove(_selected)),
                child: const Text('删除折线'),
              ),
              TextButton(
                onPressed: _updateCircle,
                child: const Text('添加/更新圆形'),
              ),
              TextButton(
                onPressed: () => setState(() => _circles.remove(_selected)),
                child: const Text('删除圆形'),
              ),
              TextButton(
                onPressed: () => _updatePolyline(fit: true),
                child: const Text('足迹取景'),
              ),
              TextButton(
                onPressed: () => _updateCircle(fit: true),
                child: const Text('围栏取景'),
              ),
            ],
          ),
          if (_show)
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _map(0)),
                  if (_two) Expanded(child: _map(1)),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _map(int index) => AMapView(
    key: ValueKey('$_generation/$index'),
    latitude: index == 0 ? 39.90923 : 31.2304,
    longitude: index == 0 ? 116.397428 : 121.4737,
    markers: _markers[index] ?? const [],
    polylines: [?_polylines[index]],
    circles: [?_circles[index]],
    onMapTap: (point) {
      if (mounted) {
        setState(
          () => _message =
              '地图 $index 底图点击：${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
        );
      }
    },
    onMarkerTap: (id) {
      if (mounted) setState(() => _message = '地图 $index 标记点击：$id');
    },
    onMapCreated: (controller) => _controllers[index] = controller,
    onCameraMove: (event) {
      if (mounted) {
        setState(
          () => _message =
              '地图 $index move / ${event.source} / ${event.position.zoom.toStringAsFixed(2)}',
        );
      }
    },
    onCameraIdle: (event) {
      if (mounted) {
        setState(
          () => _message =
              '地图 $index idle / ${event.source} / ${event.position.latitude.toStringAsFixed(5)}, ${event.position.longitude.toStringAsFixed(5)}',
        );
      }
    },
    onStatusChanged: (status) {
      if (mounted) {
        setState(() => _message = '地图 $index：${status.name}（需实际检查瓦片）');
      }
    },
    onError: (code) {
      if (mounted) setState(() => _message = '地图 $index：$code');
    },
  );
}
