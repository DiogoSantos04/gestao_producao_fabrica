import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Permite arrastar para fazer scroll também com o rato e o trackpad,
/// e não apenas por toque (útil nos ecrãs desktop com listas horizontais).
class MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
