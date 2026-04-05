import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFontScaleKey = 'clawke_font_scale';
const _kDefaultScale = 1.0;
const _kMinScale = 0.8;
const _kMaxScale = 1.4;

/// 全局字体缩放系数。
///
/// 范围 0.8–1.4，默认 1.0。持久化到 SharedPreferences。
class FontScaleNotifier extends StateNotifier<double> {
  FontScaleNotifier() : super(_kDefaultScale) {
    _load();
  }

  static double get minScale => _kMinScale;
  static double get maxScale => _kMaxScale;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kFontScaleKey);
    if (saved != null) {
      state = saved.clamp(_kMinScale, _kMaxScale);
    }
  }

  Future<void> setScale(double scale) async {
    state = scale.clamp(_kMinScale, _kMaxScale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontScaleKey, state);
  }
}

final fontScaleProvider = StateNotifierProvider<FontScaleNotifier, double>(
  (ref) => FontScaleNotifier(),
);
