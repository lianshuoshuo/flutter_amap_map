import 'package:flutter/material.dart';

import 'demo_menu.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({
    super.key,
    this.apiKey = const String.fromEnvironment('AMAP_API_KEY'),
  });

  final String apiKey;
  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: DemoMenu(apiKey: apiKey));
}
