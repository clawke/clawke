import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'mermaid_rendering_enabled';

/// Mermaid 渲染开关 Provider（默认开启，持久化到 SharedPreferences）
final mermaidEnabledProvider =
    StateNotifierProvider<MermaidEnabledNotifier, bool>((ref) {
      return MermaidEnabledNotifier();
    });

class MermaidEnabledNotifier extends StateNotifier<bool> {
  MermaidEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
