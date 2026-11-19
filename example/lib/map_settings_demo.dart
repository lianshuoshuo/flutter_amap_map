import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef _ZoomRange = ({double minZoom, double maxZoom});

class MapSettingsDemo extends StatefulWidget {
  const MapSettingsDemo({super.key});

  @override
  State<MapSettingsDemo> createState() => _MapSettingsDemoState();
}

class _MapSettingsDemoState extends State<MapSettingsDemo> {
  static const ranges = <_ZoomRange>[
    (minZoom: 3, maxZoom: 20),
    (minZoom: 12, maxZoom: 14),
    (minZoom: 17, maxZoom: 19),
  ];
  AMapController? _controller;
  _ZoomRange _requested = ranges.first;
  _ZoomRange? _effective;
  double? _zoom;
  bool _buildings = true;
  AMapType _type = AMapType.standard;
  bool _busy = false;
  AMapApprovalNumbers? _numbers;
  String? _error;

  Future<void> _run(Future<void> Function(AMapController) action) async {
    final controller = _controller;
    if (_busy || controller == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(controller);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(_ZoomRange range, bool buildings, {AMapType? type}) =>
      _run((controller) async {
        final mapType = type ?? _type;
        await controller.setOptions(
          AMapOptions(
            mapType: mapType,
            minZoom: range.minZoom,
            maxZoom: range.maxZoom,
            buildingsEnabled: buildings,
          ),
        );
        if (!mounted) return;
        setState(() {
          _requested = range;
          _buildings = buildings;
          _type = mapType;
          _effective = null;
        });
        final effective = await controller.getZoomRange();
        final camera = await controller.getCamera();
        if (mounted) {
          setState(() {
            _effective = effective;
            _zoom = camera.zoom;
          });
        }
      });

  Future<void> _readNumbers() => _run((controller) async {
    setState(() => _numbers = null);
    final numbers = await controller.getMapApprovalNumbers();
    if (mounted) setState(() => _numbers = numbers);
  });

  Future<void> _step(int delta) => _run((controller) async {
    final camera = await controller.getCamera();
    final next = camera.zoom.round() + delta;
    if (next < 3 || next > 20) {
      if (mounted) setState(() => _error = '已到公共缩放边界');
      return;
    }
    await controller.moveCamera(
      AMapCameraPosition(
        latitude: camera.latitude,
        longitude: camera.longitude,
        zoom: next.toDouble(),
      ),
    );
  });

  String _label(_ZoomRange range) {
    String level(double value) =>
        value == value.truncate() ? value.toInt().toString() : value.toString();
    return '${level(range.minZoom)}–${level(range.maxZoom)}';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _controller != null && !_busy;
    final effective = _effective;
    final numbers = _numbers;
    return Scaffold(
      appBar: AppBar(title: const Text('地图设置')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .50,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final range in ranges)
                            ChoiceChip(
                              label: Text(_label(range)),
                              selected: range == _requested,
                              onSelected: enabled
                                  ? (_) => _apply(range, _buildings)
                                  : null,
                            ),
                        ],
                      ),
                      Text(
                        'SDK 范围 ${effective == null ? '—' : _label(effective)} · 当前缩放 ${_zoom?.toStringAsFixed(2) ?? '—'}',
                      ),
                      Wrap(
                        children: [
                          IconButton(
                            tooltip: '缩小一级',
                            onPressed: enabled ? () => _step(-1) : null,
                            icon: const Icon(Icons.remove),
                          ),
                          IconButton(
                            tooltip: '放大一级',
                            onPressed: enabled ? () => _step(1) : null,
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            tooltip: _type == AMapType.standard
                                ? '切换卫星图'
                                : '切换标准图',
                            onPressed: enabled
                                ? () => _apply(
                                    _requested,
                                    _buildings,
                                    type: _type == AMapType.standard
                                        ? AMapType.satellite
                                        : AMapType.standard,
                                  )
                                : null,
                            icon: const Icon(Icons.layers_outlined),
                          ),
                          TextButton(
                            onPressed: enabled
                                ? () => _apply(_requested, !_buildings)
                                : null,
                            child: Text(_buildings ? '隐藏 3D 建筑' : '显示 3D 建筑'),
                          ),
                          TextButton(
                            onPressed: enabled ? _readNumbers : null,
                            child: const Text('读取审图号'),
                          ),
                        ],
                      ),
                      if (numbers != null) ...[
                        Text('普通地图 ${numbers.mapContent ?? 'SDK 暂未提供'}'),
                        Text('卫星影像 ${numbers.satelliteImage ?? 'SDK 暂未提供'}'),
                      ],
                      if (_error != null) Text(_error!),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: AMapView(
                  latitude: 22.5333,
                  longitude: 114.0557,
                  zoom: 18,
                  onMapCreated: (controller) {
                    _controller = controller;
                    _apply(_requested, _buildings);
                  },
                  onCameraIdle: (event) =>
                      setState(() => _zoom = event.position.zoom),
                  onError: (code) => setState(() => _error = code),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
