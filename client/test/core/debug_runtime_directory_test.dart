import 'dart:io';

import 'package:client/core/debug_runtime_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile platforms ignore configured debug runtime directory', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'clawke-debug-runtime-mobile-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final repoDir = Directory('${tempDir.path}/clawke')..createSync();
    final clientDir = Directory('${repoDir.path}/client')..createSync();
    File('${clientDir.path}/pubspec.yaml').writeAsStringSync('name: client\n');

    final androidDir = resolveDebugRuntimeDirectory(
      startDirectory: clientDir,
      debugMode: true,
      environment: const {'CLAWKE_RUNTIME_DIR': '.runtime'},
      isAndroid: true,
      isIOS: false,
    );
    final iosDir = resolveDebugRuntimeDirectory(
      startDirectory: clientDir,
      debugMode: true,
      environment: const {'CLAWKE_RUNTIME_DIR': '.runtime'},
      isAndroid: false,
      isIOS: true,
    );

    expect(androidDir, isNull);
    expect(iosDir, isNull);
  });

  test('relative runtime directory is ignored when repo cannot be found', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'clawke-debug-runtime-orphan-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final runtimeDir = resolveDebugRuntimeDirectory(
      startDirectory: tempDir,
      debugMode: true,
      environment: const {'CLAWKE_RUNTIME_DIR': '.runtime'},
      isAndroid: false,
      isIOS: false,
    );

    expect(runtimeDir, isNull);
  });

  test('absolute desktop runtime directory is still allowed', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'clawke-debug-runtime-absolute-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final runtimeDir = resolveDebugRuntimeDirectory(
      startDirectory: Directory.systemTemp,
      debugMode: true,
      environment: {'CLAWKE_RUNTIME_DIR': '${tempDir.path}/runtime'},
      isAndroid: false,
      isIOS: false,
    );

    expect(runtimeDir?.path, '${tempDir.path}/runtime');
  });
}
