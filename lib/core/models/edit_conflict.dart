/// A rejected edit, never permission to retry with a newer baseline implicitly.
class EditConflict implements Exception {
  const EditConflict(this.record, {this.deleted = false});
  final String record;
  final bool deleted;
  @override
  String toString() => deleted
      ? '$record was deleted. Your unsaved changes are kept.'
      : '$record changed in another editor. Your unsaved changes are kept.';
}
