import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

void main() {
  bootstrap(() => const ProviderScope(child: WorshipFlowApp()));
}
