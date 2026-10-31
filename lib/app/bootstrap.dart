import 'package:flutter/material.dart';

void bootstrap(Widget Function() builder) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(builder());
}
