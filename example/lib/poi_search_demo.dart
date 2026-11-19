import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'place_lookup_demo.dart';

class PoiSearchDemo extends StatefulWidget {
  const PoiSearchDemo({super.key, this.selectionCenter});

  /// In a map picker, nearby searches use the current selection as their center.
  final AMapLatLng? selectionCenter;

  @override
  State<PoiSearchDemo> createState() => _PoiSearchDemoState();
}

class _PoiSearchDemoState extends State<PoiSearchDemo> {
  static const _center = AMapLatLng(22.5431, 114.0579);
  static const _pageSize = 5;
  final _keyword = TextEditingController(text: '深圳市民中心');
  Timer? _debounce;
  int _revision = 0;
  bool _limitCity = false;
  bool _food = false;
  bool _loading = false;
  bool _nearby = false;
  int _page = 0;
  String? _status;
  List<AMapPoi> _places = [];
  List<AMapInputTip> _tips = [];
  String? get _city => _limitCity ? '深圳' : null;
  String? get _category => _food ? '050000' : null;

  void _inputsChanged() {
    _debounce?.cancel();
    final revision = ++_revision;
    final query = _keyword.text.trim();
    setState(() {
      _places = [];
      _tips = [];
      _status = null;
      _loading = false;
      _page = 0;
    });
    if (query.isNotEmpty) {
      _debounce = Timer(
        const Duration(milliseconds: 300),
        () => _suggest(query, revision),
      );
    }
  }

  Future<void> _suggest(String query, int revision) async {
    setState(() => _loading = true);
    try {
      final tips = await AMapPoiSearch.inputTips(
        query,
        city: _city,
        categoryCode: _category,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _tips = tips;
        _status = tips.isEmpty ? '没有输入提示' : '输入提示 · ${tips.length} 条';
      });
    } on PlatformException catch (error) {
      _showError(revision, '输入提示', error);
    }
  }

  void _showError(int revision, String action, PlatformException error) {
    if (!mounted || revision != _revision) return;
    setState(() {
      _loading = false;
      _status =
          '$action失败：${error.code}'
          '${error.details is int ? ' (${error.details})' : ''}';
    });
  }

  Future<void> _search({required bool nearby, int? targetPage}) async {
    _debounce?.cancel();
    final revision = ++_revision;
    final query = _keyword.text.trim();
    if (!nearby && query.isEmpty) {
      setState(() {
        _loading = false;
        _page = 0;
        _places = [];
        _tips = [];
        _status = '请输入关键词';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    final page = targetPage ?? 1;
    setState(() {
      _loading = true;
      _status = null;
      _tips = [];
      if (targetPage == null) {
        _page = 0;
        _places = [];
      }
    });
    try {
      final places = nearby
          ? await AMapPoiSearch.searchNearby(
              widget.selectionCenter ?? _center,
              categoryCode: _category,
              page: page,
              pageSize: _pageSize,
            )
          : await AMapPoiSearch.searchKeyword(
              query,
              city: _city,
              categoryCode: _category,
              page: page,
              pageSize: _pageSize,
            );
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _places = places;
        _page = page;
        _nearby = nearby;
        final mode = nearby ? '周边' : '关键词';
        _status = places.isEmpty
            ? '$mode搜索无结果'
            : '$mode搜索：${places.length} 个结果';
      });
    } on PlatformException catch (error) {
      _showError(revision, '搜索', error);
    }
  }

  void _choose(AMapLatLng point, String name, String? address) {
    Navigator.pop<MapPlaceSelection>(context, (
      coordinate: point,
      name: name,
      address: address,
    ));
  }

  void _openPlace(AMapPoi place) {
    if (widget.selectionCenter != null) {
      _choose(place.coordinate, place.name, place.address);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PlaceLookupDemo(poiId: place.id!)),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.selectionCenter == null ? 'POI 搜索' : '选择地点'),
      actions: [
        if (widget.selectionCenter == null)
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const PlaceLookupDemo()),
            ),
            child: const Text('地址查坐标'),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _keyword,
              onChanged: (_) => _inputsChanged(),
              onSubmitted: (_) => _search(nearby: false),
              decoration: const InputDecoration(labelText: '关键词'),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('关键词限深圳'),
                selected: _limitCity,
                onSelected: (value) {
                  _limitCity = value;
                  _inputsChanged();
                },
              ),
              FilterChip(
                label: const Text('餐饮'),
                selected: _food,
                onSelected: (value) {
                  _food = value;
                  _inputsChanged();
                },
              ),
            ],
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: () => _search(nearby: false),
                child: const Text('按关键词搜索'),
              ),
              TextButton(
                onPressed: () => _search(nearby: true),
                child: Text(
                  widget.selectionCenter == null ? '查市民中心周边' : '查选点周边',
                ),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_status != null) Text(_status!),
          Expanded(
            child: ListView.builder(
              itemCount: _tips.isNotEmpty ? _tips.length : _places.length,
              itemBuilder: (_, index) {
                if (_tips.isNotEmpty) {
                  final tip = _tips[index];
                  final address = [?tip.district, ?tip.address].join(' ');
                  return ListTile(
                    title: Text(tip.name),
                    subtitle: address.isEmpty ? null : Text(address),
                    onTap: () {
                      final point = tip.coordinate;
                      if (widget.selectionCenter != null && point != null) {
                        _choose(point, tip.name, tip.address);
                        return;
                      }
                      _keyword.value = TextEditingValue(
                        text: tip.name,
                        selection: TextSelection.collapsed(
                          offset: tip.name.length,
                        ),
                      );
                      _search(nearby: false);
                    },
                  );
                }
                final poi = _places[index];
                final location = poi.coordinate;
                final canOpen =
                    widget.selectionCenter != null || poi.id != null;
                return ListTile(
                  title: Text(poi.name),
                  trailing: canOpen ? const Icon(Icons.chevron_right) : null,
                  onTap: canOpen ? () => _openPlace(poi) : null,
                  subtitle: Text(
                    [
                      poi.address ?? '地址未提供',
                      poi.category ?? poi.categoryCode ?? '分类未提供',
                      'GCJ-02 ${location.latitude.toStringAsFixed(6)}, '
                          '${location.longitude.toStringAsFixed(6)}',
                    ].join('\n'),
                  ),
                );
              },
            ),
          ),
          if (_page > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: !_loading && _page > 1
                      ? () => _search(nearby: _nearby, targetPage: _page - 1)
                      : null,
                  child: const Text('上一页'),
                ),
                Text('第 $_page 页'),
                TextButton(
                  onPressed: !_loading && _places.isNotEmpty && _page < 100
                      ? () => _search(nearby: _nearby, targetPage: _page + 1)
                      : null,
                  child: const Text('下一页'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
