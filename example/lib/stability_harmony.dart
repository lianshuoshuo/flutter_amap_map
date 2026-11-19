import 'package:flutter_amap_map/flutter_amap_map_harmony.dart';
import 'package:flutter/material.dart';
import 'validation/stability_page.dart';

void main() {
  registerAMapHarmonyView();
  runApp(const MaterialApp(home: StabilityPage()));
}
