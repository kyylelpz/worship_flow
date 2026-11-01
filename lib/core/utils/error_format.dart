import 'package:flutter/material.dart';

class UserFacingError {
  final String title;
  final String message;
  final IconData icon;

  const UserFacingError(this.title, this.message, this.icon);

  factory UserFacingError.from(Object error) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('permission') ||
        raw.contains('denied') ||
        raw.contains('forbidden') ||
        raw.contains('not authorized') ||
        raw.contains('unauthorized')) {
      return const UserFacingError(
        'Permission denied',
        'You don’t have permission to do that. Ask a group admin for access.',
        Icons.lock_outline_rounded,
      );
    }
    if (raw.contains('network') || raw.contains('socket')) {
      return const UserFacingError(
        'Network error',
        'Please check your connection and try again.',
        Icons.wifi_off_rounded,
      );
    }
    return UserFacingError(
      'Something went wrong',
      error.toString(),
      Icons.error_outline_rounded,
    );
  }
}