import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef MapPlaceSelection = ({
  AMapLatLng coordinate,
  String? name,
  String? address,
});
typedef _PlaceRow = ({
  String? title,
  String description,
  AMapLatLng coordinate,
});

class PlaceLookupDemo extends StatefulWidget {
  const PlaceLookupDemo({super.key, this.poiId}) : _pickAddress = false;
  const PlaceLookupDemo.pickAddress({super.key})
    : poiId = null,
      _pickAddress = true;

  final String? poiId;
  final bool _pickAddress;

  @override
  State<PlaceLookupDemo> createState() => _PlaceLookupDemoState();
}

class _PlaceLookupDemoState extends State<PlaceLookupDemo> {
  late final _query = TextEditingController(
    text: widget.poiId ?? '深圳市福田区福中三路2010号',
  );
  final _city = TextEditingController(text: '深圳');
  int _revision = 0;
  List<_PlaceRow> _rows = const [];
  String? _message;
  bool _loading = false;
  bool get _byId => widget.poiId != null;

  @override
  void initState() {
    super.initState();
    if (_byId) _run();
  }

  String _coordinate(AMapLatLng point) =>
      'GCJ-02 ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';

  String? _region(String? province, String? city, String? district) {
    final parts = [?province, ?city, ?district];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<List<_PlaceRow>> _lookup() async {
    if (_byId) {
      final poi = await AMapPoiSearch.getById(_query.text);
      if (poi == null) return [];
      return [
        (
          title: poi.name,
          coordinate: poi.coordinate,
          description: [
            ?poi.address,
            ?poi.category,
            if (poi.categoryCode != null) '分类编码 ${poi.categoryCode}',
            ?_region(poi.province, poi.city, poi.district),
            if (poi.adCode != null) '行政区编码 ${poi.adCode}',
            if (poi.telephone != null) '电话 ${poi.telephone}',
            _coordinate(poi.coordinate),
          ].join('\n'),
        ),
      ];
    }
    final matches = await AMapGeocoder.forwardGeocode(
      _query.text,
      city: _city.text,
    );
    return [
      for (final match in matches)
        (
          title: match.formattedAddress,
          coordinate: match.coordinate,
          description: [
            if (match.level != null) '匹配级别 ${match.level}',
            ?_region(
              match.administrativeArea.province,
              match.administrativeArea.city,
              match.administrativeArea.district,
            ),
            if (match.administrativeArea.adCode != null)
              '行政区编码 ${match.administrativeArea.adCode}',
            _coordinate(match.coordinate),
          ].join('\n'),
        ),
    ];
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    _run();
  }

  Future<void> _run() async {
    final revision = ++_revision;
    final byId = _byId;
    setState(() {
      _loading = true;
      _message = null;
      _rows = const [];
    });
    List<_PlaceRow> rows = const [];
    String? message;
    try {
      rows = await _lookup();
      if (rows.isEmpty) {
        message = byId ? '未找到该 POI' : '没有匹配的地址';
      } else if (!byId) {
        message = '匹配到 ${rows.length} 个地址';
      }
    } on ArgumentError {
      message = byId ? '请输入单个 POI ID' : '请输入地址';
    } on PlatformException catch (error) {
      message =
          '查询失败 · ${error.code}${error.details is int ? ' (${error.details})' : ''}';
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _loading = false;
      _rows = rows;
      _message = message;
    });
  }

  void _edited(String _) {
    _revision++;
    if (!_loading && _rows.isEmpty && _message == null) return;
    setState(() {
      _loading = false;
      _rows = const [];
      _message = null;
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_byId ? 'POI 详情' : '地址查坐标')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _query,
            decoration: InputDecoration(labelText: _byId ? 'POI ID' : '地址'),
            onChanged: _edited,
            onSubmitted: (_) => _submit(),
          ),
          if (!_byId)
            TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: '城市（可选）'),
              onChanged: _edited,
              onSubmitted: (_) => _submit(),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _submit,
              child: Text(_byId ? '查询详情' : '查询坐标'),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_message != null) Text(_message!),
          for (final row in _rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row.title ?? '未提供格式化地址'),
              subtitle: Text(row.description),
              trailing: widget._pickAddress
                  ? const Icon(Icons.chevron_right)
                  : null,
              onTap: widget._pickAddress
                  ? () => Navigator.pop<MapPlaceSelection>(context, (
                      coordinate: row.coordinate,
                      name: null,
                      address: row.title,
                    ))
                  : null,
            ),
        ],
      ),
    ),
  );
}
