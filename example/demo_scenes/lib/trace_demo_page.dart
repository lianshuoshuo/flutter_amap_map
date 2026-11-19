import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _ink = Color(0xff1a1a1b);
const _lime = Color(0xffddf247);
const _cardBottom = 18.0;

typedef _TracePoint = ({AMapLatLng coordinate, String address, String time});

const _days = [
  (
    label: '11月17日',
    weekday: '周二',
    points: <_TracePoint>[
      (
        coordinate: AMapLatLng(22.54185, 114.05390),
        address: '福田站东北侧',
        time: '08:12',
      ),
      (
        coordinate: AMapLatLng(22.54242, 114.05595),
        address: '福田中心区步道',
        time: '08:18',
      ),
      (
        coordinate: AMapLatLng(22.54353, 114.05730),
        address: '深圳市民中心广场',
        time: '08:24',
      ),
      (
        coordinate: AMapLatLng(22.54513, 114.05824),
        address: '深圳图书馆东侧',
        time: '08:31',
      ),
      (
        coordinate: AMapLatLng(22.54571, 114.06048),
        address: '深圳音乐厅附近',
        time: '08:38',
      ),
    ],
  ),
  (
    label: '11月16日',
    weekday: '周一',
    points: <_TracePoint>[
      (
        coordinate: AMapLatLng(22.54845, 114.05240),
        address: '莲花山公园西南侧',
        time: '17:05',
      ),
      (
        coordinate: AMapLatLng(22.55008, 114.05450),
        address: '莲花山公园步道',
        time: '17:13',
      ),
      (
        coordinate: AMapLatLng(22.55086, 114.05664),
        address: '莲花山公园风筝广场附近',
        time: '17:21',
      ),
      (
        coordinate: AMapLatLng(22.54885, 114.05858),
        address: '莲花山公园南门附近',
        time: '17:28',
      ),
    ],
  ),
];

enum _Pin { start, mid, end }

class TraceDemoPage extends StatefulWidget {
  const TraceDemoPage({super.key, this.assetPrefix = 'packages/amap_example_scenes/'});

  final String assetPrefix;

  @override
  State<TraceDemoPage> createState() => _TraceDemoPageState();
}

class _TraceDemoPageState extends State<TraceDemoPage> {
  final _cardKey = GlobalKey();
  late final _icons = _loadIcons();
  AMapController? _map;
  bool _loaded = false;
  int _day = 0;
  int _selected = 0;
  String? _error;

  List<_TracePoint> get _points => _days[_day].points;

  Future<Map<(_Pin, bool), Uint8List>> _loadIcons() async {
    return {
      for (final role in _Pin.values)
        for (final selected in [false, true])
          (role, selected): Uint8List.sublistView(
            await rootBundle.load(
              '${widget.assetPrefix}assets/trace/${role.name}${selected ? '_selected' : ''}.png',
            ),
          ),
    };
  }

  _Pin _role(int index) {
    if (index == 0) return _Pin.start;
    if (index == _points.length - 1) return _Pin.end;
    return _Pin.mid;
  }

  Future<void> _fit() async {
    final map = _map;
    final cardHeight = _cardKey.currentContext?.size?.height;
    if (map == null || !_loaded || cardHeight == null) return;
    try {
      await map.fitBounds(
        AMapBounds.fromPoints(_points.map((point) => point.coordinate)),
        padding: EdgeInsets.fromLTRB(42, 44, 42, cardHeight + _cardBottom + 27),
        animated: true,
      );
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code);
    }
  }

  void _fitAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit();
    });
  }

  void _selectDay(int day) {
    if (day == _day) return;
    setState(() {
      _day = day;
      _selected = 0;
      _error = null;
    });
    if (_loaded) _fitAfterLayout();
  }

  Future<void> _selectPoint(int index) async {
    final point = _points[index].coordinate;
    setState(() {
      _selected = index;
      _error = null;
    });
    try {
      await _map?.moveCamera(
        AMapCameraPosition(
          latitude: point.latitude,
          longitude: point.longitude,
          zoom: 17,
        ),
        animated: true,
      );
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfffafafa),
    appBar: AppBar(
      title: const Text('足迹', style: TextStyle(fontWeight: FontWeight.w700)),
      actions: [
        TextButton(onPressed: _loaded ? _fit : null, child: const Text('整段取景')),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _days.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: ChoiceChip(
                      label: Text('${_days[i].label}  ${_days[i].weekday}'),
                      selected: _day == i,
                      showCheckmark: false,
                      selectedColor: _ink,
                      labelStyle: TextStyle(
                        color: _day == i ? _lime : _ink,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => _selectDay(i),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _icons,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('演示标记加载失败'));
                }
                final icons = snapshot.data;
                if (icons == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final start = _days.first.points.first.coordinate;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AMapView(
                      latitude: start.latitude,
                      longitude: start.longitude,
                      zoom: 15,
                      polylines: [
                        AMapPolyline(
                          id: 'trace',
                          points: _points.map((p) => p.coordinate).toList(),
                          width: 3,
                          color: const Color(0xff333333),
                        ),
                      ],
                      markers: [
                        for (var i = 0; i < _points.length; i++)
                          AMapMarker(
                            id: 'trace-point-$i',
                            latitude: _points[i].coordinate.latitude,
                            longitude: _points[i].coordinate.longitude,
                            pngBytes: icons[(_role(i), i == _selected)]!,
                            width: _markerSize(i),
                            height: _markerSize(i),
                            anchorU: .5,
                            anchorV: .5,
                            zIndex: i == _selected
                                ? 10
                                : (_role(i) == _Pin.mid ? 2 : 3),
                          ),
                      ],
                      onMapCreated: (map) => _map = map,
                      onStatusChanged: (status) {
                        if (status != AMapStatus.loaded || _loaded) return;
                        setState(() => _loaded = true);
                        _fitAfterLayout();
                      },
                      onError: (code) => setState(() => _error = code),
                    ),
                    if (_error != null)
                      Positioned(
                        top: 8,
                        left: 12,
                        right: 12,
                        child: Text('地图状态：$_error'),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: _cardBottom,
                      child: _buildCard(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  double _markerSize(int index) => switch (_role(index)) {
    _Pin.start || _Pin.end => 26,
    _Pin.mid when index == _selected => 23,
    _Pin.mid => 16,
  };

  Widget _buildCard() {
    final point = _points[_selected];
    return Material(
      key: _cardKey,
      color: Colors.white,
      elevation: 6,
      shadowColor: const Color(0x24000000),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: _lime,
                  foregroundColor: _ink,
                  child: Icon(Icons.pets, size: 15),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '豆豆',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Text(
                      '模拟定位',
                      style: TextStyle(color: _lime, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    point.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xff555555)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  point.time,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Divider(height: 14),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _points.length,
                separatorBuilder: (_, _) => const Center(
                  child: SizedBox(
                    width: 12,
                    child: Divider(color: Color(0xffbcbcbc), thickness: 1),
                  ),
                ),
                itemBuilder: (context, index) => Semantics(
                  button: true,
                  selected: _selected == index,
                  label: '轨迹点 ${index + 1}',
                  child: InkWell(
                    key: ValueKey('trace-dot-$index'),
                    onTap: () => _selectPoint(index),
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 44,
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _selected == index ? _lime : Colors.white,
                            border: Border.all(color: _ink, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
