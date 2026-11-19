import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'place_lookup_demo.dart';
import 'poi_search_demo.dart';

/// Demonstrates selecting a coordinate by moving the map under a fixed reticle.
class CalibrationDemo extends StatefulWidget {
  const CalibrationDemo({super.key, this.fence = false});

  final bool fence;

  @override
  State<CalibrationDemo> createState() => _CalibrationDemoState();
}

class _CalibrationDemoState extends State<CalibrationDemo> {
  AMapController? _controller;
  static const _home = AMapLatLng(22.5431, 114.0579);
  AMapLatLng _selected = _home;
  AMapCameraEvent? _idle;

  int _cameraAction = 0;
  int _lookupGeneration = 0;
  String? _placeName;
  String _address = '正在查询地址…';
  String? _candidates;

  @override
  void initState() {
    super.initState();
    _lookup(_home);
  }

  void _onIdle(AMapCameraEvent event) {
    setState(() => _idle = event);
    final next = AMapLatLng(event.position.latitude, event.position.longitude);
    if (event.reason == AMapCameraReason.userDrag &&
        (next.latitude != _selected.latitude ||
            next.longitude != _selected.longitude)) {
      _cameraAction++;
      _select(next);
    }
  }

  void _select(AMapLatLng point, {String? name, String? address}) {
    setState(() {
      _selected = point;
      _placeName = name;
      _address = address == null ? '正在查询地址…' : '地址：$address';
      _candidates = null;
      _error = null;
    });
    _lookup(point, suppliedAddress: address);
  }

  Future<void> _lookup(AMapLatLng coordinate, {String? suppliedAddress}) async {
    final generation = ++_lookupGeneration;
    try {
      final result = await AMapGeocoder.reverseGeocode(coordinate);
      if (!mounted || generation != _lookupGeneration) return;
      final area = result.administrativeArea;
      setState(() {
        _address = '地址：${suppliedAddress ?? result.formattedAddress}';
        _candidates =
            '行政区 ${area.adCode ?? '—'}'
            ' · POI ${result.pois.length} · AOI ${result.aois.length}';
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        final code =
            '${error.code}${error.details is int ? ' (${error.details})' : ''}';
        if (suppliedAddress == null) {
          _address = '地址查询失败：$code';
        } else {
          _candidates = '附近信息查询失败：$code';
        }
      });
    }
  }

  Future<void> _pick({required bool byAddress}) async {
    final controller = _controller;
    if (controller == null) return;
    final center = _selected;
    final route = MaterialPageRoute<MapPlaceSelection>(
      builder: (_) => byAddress
          ? const PlaceLookupDemo.pickAddress()
          : PoiSearchDemo(selectionCenter: center),
    );
    final place = await Navigator.of(context).push(route);
    if (!mounted || place == null) return;
    final action = ++_cameraAction;
    // Apply the move after the map is visible again.
    await route.completed;
    bool current() =>
        mounted && action == _cameraAction && controller == _controller;
    if (!current()) return;
    try {
      final camera = await controller.getCamera();
      if (!current()) return;
      await controller.moveCamera(
        AMapCameraPosition(
          latitude: place.coordinate.latitude,
          longitude: place.coordinate.longitude,
          zoom: camera.zoom,
        ),
      );
      if (!current()) return;
      _select(place.coordinate, name: place.name, address: place.address);
    } on PlatformException catch (error) {
      if (current()) setState(() => _error = '地图移动失败：${error.code}');
    }
  }

  Future<void> _recenter() async {
    final action = ++_cameraAction;
    try {
      await _controller?.moveCamera(
        AMapCameraPosition(
          latitude: _home.latitude,
          longitude: _home.longitude,
          zoom: 16,
        ),
        animated: true,
      );
    } on PlatformException catch (error) {
      if (mounted && action == _cameraAction) {
        setState(() => _error = error.code);
      }
    }
  }

  AMapType _type = AMapType.standard;
  bool _locked = true;
  bool _controls = false;
  bool _applying = false;
  String? _error;

  Future<void> _apply({AMapType? type, bool? locked, bool? controls}) async {
    final controller = _controller;
    if (controller == null || _applying) return;
    final nextType = type ?? _type;
    final nextLocked = locked ?? _locked;
    final nextControls = controls ?? _controls;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await controller.setOptions(
        AMapOptions(
          mapType: nextType,
          zoomEnabled: widget.fence || !nextLocked,
          rotateEnabled: !nextLocked,
          tiltEnabled: !nextLocked,
          inertiaEnabled: !nextLocked,
          compassEnabled: nextControls,
          scaleEnabled: nextControls,
        ),
      );
      if (!mounted) return;
      setState(() {
        _type = nextType;
        _locked = nextLocked;
        _controls = nextControls;
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _controller != null && !_applying;
    final idle = _idle;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fence ? '围栏选点' : '位置校准'),
        actions: [
          TextButton(
            onPressed: enabled ? () => _pick(byAddress: false) : null,
            child: const Text('搜地点'),
          ),
          TextButton(
            onPressed: enabled ? () => _pick(byAddress: true) : null,
            child: const Text('地址查坐标'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Wrap(
              children: [
                TextButton(
                  onPressed: enabled
                      ? () => _apply(
                          type: _type == AMapType.standard
                              ? AMapType.satellite
                              : AMapType.standard,
                        )
                      : null,
                  child: Text(_type == AMapType.standard ? '切换卫星图' : '切换标准图'),
                ),
                TextButton(
                  onPressed: enabled ? () => _apply(locked: !_locked) : null,
                  child: Text(_locked ? '切换自由模式' : '切换校准模式'),
                ),
                TextButton(
                  onPressed: enabled
                      ? () => _apply(controls: !_controls)
                      : null,
                  child: Text(_controls ? '隐藏地图控件' : '显示地图控件'),
                ),
                TextButton(
                  onPressed: enabled ? _recenter : null,
                  child: const Text('程序回中'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '选点 ${_selected.latitude.toStringAsFixed(6)}, ${_selected.longitude.toStringAsFixed(6)}',
                  ),
                  if (idle != null)
                    Text(
                      '地图中心 ${idle.position.latitude.toStringAsFixed(6)}, ${idle.position.longitude.toStringAsFixed(6)}',
                    ),
                  Text(
                    _error ??
                        (idle == null
                            ? '拖动地图使目标对准准星'
                            : '${idle.reason.name} · 缩放 ${idle.position.zoom.toStringAsFixed(2)}'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: [
                  if (_placeName != null)
                    Text(
                      _placeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(_address, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (_candidates != null) Text(_candidates!),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AMapView(
                    latitude: _home.latitude,
                    longitude: _home.longitude,
                    circles: [
                      if (widget.fence)
                        AMapCircle(
                          id: 'fence',
                          center: _selected,
                          radiusMeters: 150,
                        ),
                    ],
                    zoom: 16,
                    onMapCreated: (controller) {
                      _controller = controller;
                      _apply();
                    },
                    onCameraIdle: _onIdle,
                    onError: (code) => setState(() => _error = code),
                  ),
                  const IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.add,
                        size: 44,
                        color: Colors.red,
                        shadows: [Shadow(color: Colors.white, blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
