import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const _runtimeDirFromDefine = String.fromEnvironment('CLAWKE_RUNTIME_DIR');

Directory? resolveDebugRuntimeDirectory({
  Directory? startDirectory,
  bool debugMode = kDebugMode,
  Map<String, String>? environment,
  bool? isAndroid,
  bool? isIOS,
}) {
  if (!debugMode) return null;
  if (_isMobilePlatform(isAndroid: isAndroid, isIOS: isIOS)) return null;

  final configuredPath = _configuredRuntimePath(environment);
  if (configuredPath == null) {
    return null;
  }

  if (p.isAbsolute(configuredPath)) {
    return Directory(p.normalize(configuredPath));
  }

  final repoDir = _findRepoDirectory(startDirectory);
  if (repoDir == null) {
    return null;
  }

  return Directory(p.normalize(p.join(repoDir.path, configuredPath)));
}

bool _isMobilePlatform({bool? isAndroid, bool? isIOS}) {
  return (isAndroid ?? Platform.isAndroid) || (isIOS ?? Platform.isIOS);
}

String? _configuredRuntimePath(Map<String, String>? environment) {
  final raw = _runtimeDirFromDefine.isNotEmpty
      ? _runtimeDirFromDefine
      : (environment ?? Platform.environment)['CLAWKE_RUNTIME_DIR'];
  final trimmed = raw?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Directory? _findRepoDirectory(Directory? startDirectory) {
  for (final start in _debugSearchStarts(startDirectory)) {
    final clientDir = _findClientDirectory(start);
    if (clientDir == null) continue;
    return clientDir.parent;
  }
  return null;
}

List<Directory> _debugSearchStarts(Directory? startDirectory) {
  if (startDirectory != null) return [startDirectory];
  return [Directory.current, File(Platform.resolvedExecutable).parent];
}

Directory? _findClientDirectory(Directory start) {
  var current = start.absolute;
  for (var depth = 0; depth < 24; depth += 1) {
    final directClient = Directory('${current.path}/client');
    if (_isFlutterClientDirectory(directClient)) return directClient;
    if (_isFlutterClientDirectory(current)) return current;

    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return null;
}

bool _isFlutterClientDirectory(Directory dir) {
  final name = dir.path.split(Platform.pathSeparator).last;
  return name == 'client' && File('${dir.path}/pubspec.yaml').existsSync();
}
