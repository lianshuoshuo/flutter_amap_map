import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _sdk = MethodChannel('dev.hscw.amap_flutter_bridge/sdk');

/// Real SDK lifecycle exercise. Run only with an authorized test Key and consent.
class StabilityPage extends StatefulWidget {
  const StabilityPage({super.key});
  @override
  State<StabilityPage> createState() => _StabilityPageState();
}

class _StabilityPageState extends State<StabilityPage> {
  bool _running = false;
  bool _consent = false;
  int _generation = 0;
  int _count = 0;
  String _message = '勾选已授权的高德隐私同意后开始真实 SDK 稳定性测试';
  final Set<int> _loaded = {};
  final List<String> _errors = [];

  @override
  void initState() {
    super.initState();
    // For local test operators who have already authorized SDK privacy consent.
    if (const bool.fromEnvironment('AMAP_STABILITY_AUTOSTART')) {
      _consent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_run());
      });
    }
  }

  void _record(String event, [Map<String, Object?> data = const {}]) {
    final line = jsonEncode({
      'timestamp': DateTime.now().toIso8601String(),
      'event': event,
      ...data,
    });
    File('${Directory.systemTemp.path}/amap_stability.jsonl')
        .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    debugPrint('AMAP_STABILITY $line');
  }

  Future<int> _nativeCount() async =>
      (await _sdk.invokeMethod<int>('activeMapCount'))!;

  Future<void> _waitFor(bool Function() condition, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (!mounted) throw StateError('test_page_disposed');
      if (DateTime.now().isAfter(deadline)) throw StateError('condition_timeout');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _remove() async {
    if (!mounted) return;
    setState(() => _count = 0);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (await _nativeCount() != 0) {
      if (DateTime.now().isAfter(deadline)) throw StateError('native_view_not_released');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Allow platform-view disposal and GPU cleanup to settle before next creation.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (await _nativeCount() != 0) throw StateError('late_native_view_after_dispose');
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      await AMapSdk.initialize(
        apiKey: const String.fromEnvironment('AMAP_API_KEY'),
        privacyAgreed: _consent,
      );
      if (!mounted) return;
      _record('start');
      for (var cycle = 0; cycle < 80; cycle++) {
        if (!mounted) return;
        final rapid = cycle >= 30;
        final count = cycle.isEven ? 1 : 2;
        _loaded.clear();
        _errors.clear();
        setState(() {
          _generation++;
          _count = count;
          _message = '${rapid ? '创建中退出' : '等待真实加载'} ${cycle + 1}/80';
        });
        if (rapid) {
          await Future<void>.delayed(Duration(milliseconds: cycle.isEven ? 50 : 150));
        } else {
          await _waitFor(() => _loaded.length == count || _errors.isNotEmpty,
              const Duration(seconds: 30));
          final nativeCount = await _nativeCount();
          if (nativeCount != count) throw StateError('native_count=$nativeCount expected=$count');
        }
        if (_errors.isNotEmpty) throw StateError(_errors.join(','));
        await _remove();
        if (!mounted) return;
        _record('cycle', {'cycle': cycle + 1, 'rapid': rapid, 'expected': count,
          'nativeAfterDispose': await _nativeCount()});
      }
      if (!mounted) return;
      setState(() { _count = 2; _generation++; _loaded.clear(); _message = '压力循环通过，双地图保活观察中'; });
      await _waitFor(() => _loaded.length == 2 || _errors.isNotEmpty,
          const Duration(seconds: 30));
      if (_errors.isNotEmpty) throw StateError(_errors.join(','));
      if (await _nativeCount() != 2) throw StateError('dual_native_count');
      _record('cycles_complete', {'cycles': 80, 'nativeCount': await _nativeCount()});
      await Future<void>.delayed(const Duration(minutes: 2));
      if (!mounted) return;
      if (_errors.isNotEmpty) throw StateError(_errors.join(','));
      if (await _nativeCount() != 2) throw StateError('retained_native_count');
      if (!mounted) return;
      setState(() => _message = '通过：80 轮循环与 2 分钟保活；请继续前后台验证');
      _record('pass', {'cycles': 80, 'nativeCount': await _nativeCount()});
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _fail(Object error) {
    final reason = error is PlatformException ? 'platform:${error.code}' : error.toString();
    try {
      _record('fail', {'reason': reason, 'generation': _generation});
    } on FileSystemException {
      debugPrint('AMAP_STABILITY event_log_write_failed');
    }
    if (mounted) setState(() => _message = '失败：$reason');
  }

  Future<void> _clear() async {
    setState(() => _running = true);
    try {
      await _remove();
      if (!mounted) return;
      _record('cleared', {'nativeCount': await _nativeCount()});
      if (mounted) setState(() => _message = '地图已销毁，可采集空载内存或再次验证');
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    return Scaffold(
    appBar: AppBar(title: const Text('地图稳定性验证')),
    body: SafeArea(child: Column(children: [
      Text(_message),
      if (!_running && _count == 0) ...[
        CheckboxListTile(value: _consent, title: const Text('已阅读并同意高德隐私政策'),
          onChanged: (value) => setState(() => _consent = value == true)),
        FilledButton(onPressed: _consent ? _run : null, child: const Text('开始稳定性验证')),
      ],
      if (!_running && _count > 0)
        OutlinedButton(onPressed: _clear, child: const Text('销毁地图并准备再次验证')),
      if (_count > 0) Expanded(child: Row(children: [
        for (var index = 0; index < _count; index++) Expanded(child: AMapView(
          key: ValueKey('$_generation/$index'),
          latitude: index == 0 ? 39.90923 : 31.2304,
          longitude: index == 0 ? 116.397428 : 121.4737,
          onStatusChanged: (status) {
            if (!mounted || generation != _generation) return;
            if (status == AMapStatus.loaded) _loaded.add(index);
            if (status == AMapStatus.failed) _errors.add('native_failed_$index');
          },
          onError: (error) {
            if (!mounted || generation != _generation) return;
            _errors.add(error);
            _record('map_error', {'code': error});
          },
        )),
      ])),
    ])),
  );
  }
}
