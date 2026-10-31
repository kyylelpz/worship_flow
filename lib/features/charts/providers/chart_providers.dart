import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Personal, in-memory offsets by arrangement; never written to shared data.
final personalTransposeProvider =
    StateProvider.family<int, String>((ref, id) => 0);
