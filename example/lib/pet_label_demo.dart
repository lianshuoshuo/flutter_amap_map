import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PetLabelDemo extends StatefulWidget {
  const PetLabelDemo({super.key, required this.markerPng});

  final Uint8List markerPng;

  @override
  State<PetLabelDemo> createState() => _PetLabelDemoState();
}

class _PetLabelDemoState extends State<PetLabelDemo> {
  static const _pet = AMapLatLng(22.54365, 114.0585);
  static const _markerHeight = 48.0;
  static const _labelWidth = 112.0;
  static const _labelHeight = 30.0;
  static const _radarSize = 144.0;

  late final _marker = AMapMarker(
    id: 'sample-pet',
    latitude: _pet.latitude,
    longitude: _pet.longitude,
    pngBytes: widget.markerPng,
    width: 36,
    height: _markerHeight,
  );

  AMapController? _map;
  Offset? _anchor;
  Size? _viewport;
  Timer? _settledProjection;
  bool _projecting = false;
  bool _pending = false;
  String? _error;

  Future<void> _refreshAnchor() async {
    _pending = true;
    final map = _map;
    if (map == null || _projecting) return;

    _projecting = true;
    try {
      while (mounted && _pending) {
        _pending = false;
        try {
          final anchor = await map.projectToScreen(_pet);
          if (!mounted) return;
          setState(() {
            _anchor = anchor;
            _error = null;
          });
        } on PlatformException catch (error) {
          if (!mounted) return;
          setState(() {
            _anchor = null;
            _error = error.code;
          });
        }
      }
    } finally {
      _projecting = false;
    }
  }

  void _refreshAfterNativeChange() {
    _refreshAnchor();
    _settledProjection?.cancel();
    // The SDK can update the surface or change only its anchor without a
    // camera callback. Read the settled projection once more.
    _settledProjection = Timer(
      const Duration(milliseconds: 250),
      _refreshAnchor,
    );
  }

  Future<void> _recenter({Offset? target}) async {
    try {
      await _map?.moveCamera(
        AMapCameraPosition(
          latitude: _pet.latitude,
          longitude: _pet.longitude,
          zoom: 16,
        ),
        animated: true,
        targetScreenPoint: target,
      );
      if (mounted) _refreshAfterNativeChange();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code);
    }
  }

  @override
  void dispose() {
    _settledProjection?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('查找宠物')),
    body: SafeArea(
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: _map == null || _viewport == null
                    ? null
                    : () => _recenter(target: _radarCenter(_viewport!)),
                child: const Text('回到雷达圈'),
              ),
              TextButton(
                onPressed: _map == null ? null : () => _recenter(),
                child: const Text('地图居中'),
              ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                if (_viewport != size) {
                  final resized = _viewport != null;
                  _viewport = size;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (resized) {
                      _refreshAfterNativeChange();
                    } else {
                      _refreshAnchor();
                    }
                  });
                }
                final anchor = _anchor;
                final radar = _radarCenter(size);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AMapView(
                      latitude: 22.5431,
                      longitude: 114.0579,
                      zoom: 16,
                      markers: [_marker],
                      onMapCreated: (controller) {
                        setState(() => _map = controller);
                        _refreshAnchor();
                      },
                      onCameraMove: (_) => _refreshAnchor(),
                      onCameraIdle: (_) => _refreshAnchor(),
                      onStatusChanged: (status) {
                        if (status == AMapStatus.loaded) _refreshAnchor();
                      },
                      onError: (code) => setState(() => _error = code),
                    ),
                    Positioned(
                      left: radar.dx - _radarSize / 2,
                      top: radar.dy - _radarSize / 2,
                      width: _radarSize,
                      height: _radarSize,
                      child: IgnorePointer(
                        child: Semantics(
                          label: '雷达圈',
                          child: const _RadarRing(),
                        ),
                      ),
                    ),
                    if (anchor != null && (Offset.zero & size).contains(anchor))
                      Positioned(
                        left: anchor.dx - _labelWidth / 2,
                        top: anchor.dy - _markerHeight - _labelHeight - 2,
                        width: _labelWidth,
                        height: _labelHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF063A52),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Text(
                                '演示宠物',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_error != null)
                      Positioned(left: 8, top: 8, child: Text('投影状态：$_error')),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Offset _radarCenter(Size size) => Offset(size.width * .40, size.height * .32);
}

class _RadarRing extends StatelessWidget {
  const _RadarRing();

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      for (final diameter in [144.0, 100.0, 56.0])
        Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xff006d77), width: 1.5),
          ),
        ),
    ],
  );
}
