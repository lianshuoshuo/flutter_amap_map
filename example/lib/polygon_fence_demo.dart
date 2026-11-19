import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PolygonFenceDemo extends StatefulWidget {
  const PolygonFenceDemo({super.key});

  @override
  State<PolygonFenceDemo> createState() => _PolygonFenceDemoState();
}

class _PolygonFenceDemoState extends State<PolygonFenceDemo> {
  static const _initial = [
    AMapLatLng(22.5450, 114.0563),
    AMapLatLng(22.5445, 114.0594),
    AMapLatLng(22.5420, 114.0591),
    AMapLatLng(22.5428, 114.0576),
    AMapLatLng(22.5417, 114.0565),
  ];
  static AMapPolygon _polygon(List<AMapLatLng> points, bool orange) =>
      AMapPolygon(
        id: 'demo-fence',
        points: points,
        strokeWidth: orange ? 5 : 3,
        strokeColor: orange ? const Color(0xFFD84315) : const Color(0xFF00695C),
        fillColor: orange ? const Color(0x66FF8A50) : const Color(0x6634C6AD),
      );

  final _surface = GlobalKey();
  AMapController? _map;
  AMapPolygon? _fence = _polygon(_initial, false);
  bool _orange = false;
  bool _showHandles = true;
  int _selected = 0;
  String? _error;
  String? _projectionError;
  Size _size = Size.zero;
  List<Offset> _anchors = [];
  bool _projecting = false;
  bool _refreshPending = false;
  Timer? _settle;
  int? _pointer;
  Offset _lastPointerPosition = Offset.zero;
  Offset _grabOffset = Offset.zero;
  int _editGeneration = 0;
  ({int vertex, Offset point, int generation})? _pendingDrag;
  bool _unprojecting = false;

  Future<void> _refresh() async {
    _refreshPending = true;
    final map = _map;
    if (_projecting || map == null || !mounted) return;
    _projecting = true;
    try {
      while (mounted && _refreshPending) {
        _refreshPending = false;
        final fence = _fence;
        final size = _size;
        if (fence == null || !_showHandles || size.isEmpty) continue;
        try {
          final anchors = await Future.wait(
            fence.points.map(map.projectToScreen),
          );
          if (mounted &&
              identical(fence, _fence) &&
              _size == size &&
              _showHandles) {
            setState(() {
              _anchors = anchors;
              _projectionError = null;
            });
          }
        } on PlatformException catch (error) {
          if (mounted && identical(fence, _fence)) {
            _cancelDrag();
            setState(() {
              _anchors = [];
              _projectionError = error.code;
            });
          }
        }
      }
    } finally {
      _projecting = false;
    }
  }

  void _refreshAfterLayout() {
    if (!mounted) return;
    _refresh();
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 250), _refresh);
  }

  Offset _local(Offset global) =>
      (_surface.currentContext!.findRenderObject()! as RenderBox).globalToLocal(
        global,
      );

  void _begin(int vertex, PointerDownEvent event) {
    if (_pointer != null) return;
    _editGeneration++;
    _pendingDrag = null;
    _pointer = event.pointer;
    _lastPointerPosition = event.position;
    _grabOffset = _anchors[vertex] - _local(event.position);
    setState(() {
      _selected = vertex;
      _error = null;
    });
  }

  void _drag(PointerEvent event) {
    if (_pointer != event.pointer ||
        event.position == _lastPointerPosition ||
        _size.width < 1 ||
        _size.height < 1) {
      return;
    }
    _lastPointerPosition = event.position;
    final local = _local(event.position) + _grabOffset;
    final point = Offset(
      local.dx.clamp(0.0, _size.width - 1),
      local.dy.clamp(0.0, _size.height - 1),
    );
    _pendingDrag = (
      vertex: _selected,
      point: point,
      generation: _editGeneration,
    );
    _applyDrag();
  }

  Future<void> _applyDrag() async {
    final map = _map;
    if (_unprojecting || map == null) return;
    _unprojecting = true;
    try {
      while (mounted && _pendingDrag != null) {
        final drag = _pendingDrag!;
        _pendingDrag = null;
        try {
          final coordinate = await map.unprojectFromScreen(drag.point);
          final fence = _fence;
          if (!mounted || drag.generation != _editGeneration || fence == null) {
            continue;
          }
          final points = fence.points.toList()..[drag.vertex] = coordinate;
          final next = _polygon(points, _orange);
          setState(() {
            _fence = next;
            _error = null;
          });
          _refresh();
        } on PlatformException catch (error) {
          if (mounted && drag.generation == _editGeneration) {
            setState(() => _error = error.code);
          }
        } on ArgumentError {
          if (mounted && drag.generation == _editGeneration) {
            setState(() => _error = '围栏至少需要三个不同顶点');
          }
        }
      }
    } finally {
      _unprojecting = false;
    }
  }

  void _cancelDrag() {
    _editGeneration++;
    _pendingDrag = null;
    _pointer = null;
  }

  void _toggleFence() {
    _cancelDrag();
    setState(() {
      _fence = _fence == null ? _polygon(_initial, _orange) : null;
      _anchors = [];
      _selected = 0;
      _error = null;
      _projectionError = null;
    });
    if (_fence != null) _fit();
  }

  Future<void> _fit() async {
    final fence = _fence;
    if (fence == null || _map == null) return;
    try {
      await _map!.fitBounds(
        AMapBounds.fromPoints(fence.points),
        padding: const EdgeInsets.all(44),
      );
      if (mounted) _refreshAfterLayout();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code);
    }
  }

  Widget _handle(int i, Offset point) => Positioned(
    key: ValueKey('vertex-$i'),
    left: point.dx - 20,
    top: point.dy - 20,
    width: 40,
    height: 40,
    child: Semantics(
      label: '顶点 ${i + 1}',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _begin(i, e),
        onPointerMove: _drag,
        onPointerUp: (e) {
          if (_pointer == e.pointer) {
            _drag(e);
            _pointer = null;
          }
        },
        onPointerCancel: (e) {
          if (_pointer == e.pointer) _cancelDrag();
        },
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == _selected ? const Color(0xFF312B6B) : Colors.white,
              border: Border.all(color: const Color(0xFF312B6B), width: 2),
            ),
            alignment: Alignment.center,
            child: ExcludeSemantics(
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 11,
                  color: i == _selected
                      ? Colors.white
                      : const Color(0xFF312B6B),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _settle?.cancel();
    _cancelDrag();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fence = _fence;
    final selected = fence?.points[_selected];
    return Scaffold(
      appBar: AppBar(title: const Text('不规则围栏')),
      body: SafeArea(
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: _map == null ? null : _toggleFence,
                  child: Text(fence == null ? '添加围栏' : '删除围栏'),
                ),
                TextButton(
                  onPressed: fence == null
                      ? null
                      : () {
                          setState(() {
                            _orange = !_orange;
                            _fence = _polygon(fence.points, _orange);
                          });
                          _refresh();
                        },
                  child: const Text('换样式'),
                ),
                TextButton(
                  onPressed: fence == null
                      ? null
                      : () {
                          _cancelDrag();
                          setState(() {
                            _showHandles = !_showHandles;
                            _anchors = [];
                            _projectionError = null;
                          });
                          _refresh();
                        },
                  child: Text(_showHandles ? '隐藏手柄' : '显示手柄'),
                ),
                TextButton(
                  onPressed: fence == null || _map == null ? null : _fit,
                  child: const Text('围栏取景'),
                ),
              ],
            ),
            Text(
              _error ??
                  _projectionError ??
                  (selected == null
                      ? '围栏已删除'
                      : '顶点 ${_selected + 1} · ${selected.latitude.toStringAsFixed(6)}, ${selected.longitude.toStringAsFixed(6)}'),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final size = constraints.biggest;
                  if (_size != size) {
                    _cancelDrag();
                    _anchors = [];
                    _size = size;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _refreshAfterLayout(),
                    );
                  }
                  return Stack(
                    key: _surface,
                    fit: StackFit.expand,
                    children: [
                      AMapView(
                        latitude: 22.54335,
                        longitude: 114.05785,
                        zoom: 16,
                        polygons: [?fence],
                        onMapCreated: (map) {
                          setState(() => _map = map);
                          _refresh();
                        },
                        onStatusChanged: (status) {
                          if (status == AMapStatus.loaded) {
                            _refreshAfterLayout();
                          }
                        },
                        onCameraMove: (_) => _refresh(),
                        onCameraIdle: (_) => _refresh(),
                        onError: (code) => setState(() => _error = code),
                      ),
                      if (_showHandles && fence != null)
                        for (var i = 0; i < _anchors.length; i++)
                          if ((Offset.zero & size).contains(_anchors[i]) ||
                              (_pointer != null && i == _selected))
                            _handle(i, _anchors[i]),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
