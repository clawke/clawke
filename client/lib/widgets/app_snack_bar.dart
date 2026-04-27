import 'package:flutter/material.dart';

void showAppSnackBar(
  BuildContext context,
  String message, {
  Duration? duration,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= 720;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(seconds: 4),
      width: isWide ? 480 : null,
      margin: isWide ? null : const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );
}
