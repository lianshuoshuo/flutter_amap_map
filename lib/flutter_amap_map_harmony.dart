/// HarmonyOS NEXT platform-view registration for the OHOS Flutter SDK.
/// Call [registerAMapHarmonyView] before running the shared Flutter UI.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/amap.dart';

/// Import only from an OHOS Flutter entry point.
void registerAMapHarmonyView() {
  amapViewFactory = (parameters, onCreated) => CustomPaint(
    foregroundPainter: _ClearMapPainter(),
    child: OhosView(
      viewType: amapViewType,
      layoutDirection: TextDirection.ltr,
      creationParams: parameters,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: onCreated,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    ),
  );
}

class _ClearMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(_ClearMapPainter oldDelegate) => false;
}
