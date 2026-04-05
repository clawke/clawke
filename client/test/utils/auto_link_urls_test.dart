import 'package:flutter_test/flutter_test.dart';

// 从 markdown_widget.dart 提取的 _autoLinkUrls 函数（保持一致）
String autoLinkUrls(String text) {
  // 1. 先找出所有已有 markdown 链接 [text](url) 的范围
  final mdLinkRe = RegExp(r'\[([^\]]*)\]\([^\)]+\)');
  final protectedRanges = <(int, int)>[];
  for (final m in mdLinkRe.allMatches(text)) {
    protectedRanges.add((m.start, m.end));
  }

  // 2. 先处理 <URL> 角括号自动链接语法：剥离角括号
  var processed = text.replaceAllMapped(
    RegExp(r'<(https?://[^\s>]+)>'),
    (match) => match.group(1)!,
  );

  // 3. 匹配所有 URL，但跳过在 protected 范围内的
  final urlRe = RegExp(r'\b(https?://[^\s\)\]]+)');
  return processed.replaceAllMapped(urlRe, (match) {
    for (final (start, end) in protectedRanges) {
      if (match.start >= start && match.end <= end) {
        return match[0]!;
      }
    }
    final url = match[1]!;
    return '[$url]($url)';
  });
}

void main() {
  group('autoLinkUrls', () {
    test('裸 URL 转为 markdown 链接', () {
      expect(
        autoLinkUrls('🔗 https://github.com/foo'),
        '🔗 [https://github.com/foo](https://github.com/foo)',
      );
    });

    test('标准 markdown 链接不变', () {
      expect(
        autoLinkUrls('[Google](https://www.google.com)'),
        '[Google](https://www.google.com)',
      );
    });

    test('URL 作为 link text 的 markdown 链接不变', () {
      expect(
        autoLinkUrls('🔗 [https://ainews.com/p/openai](https://ainews.com/p/openai)'),
        '🔗 [https://ainews.com/p/openai](https://ainews.com/p/openai)',
      );
    });

    test('混合内容：已有链接不变，裸 URL 转换', () {
      expect(
        autoLinkUrls('看 [这里](https://example.com) 和 https://raw.url.com'),
        '看 [这里](https://example.com) 和 [https://raw.url.com](https://raw.url.com)',
      );
    });

    test('多个裸 URL 全部转换', () {
      const input = '链接1 https://a.com 链接2 https://b.com';
      expect(
        autoLinkUrls(input),
        '链接1 [https://a.com](https://a.com) 链接2 [https://b.com](https://b.com)',
      );
    });

    test('无 URL 的纯文本不变', () {
      expect(autoLinkUrls('这是一段普通文本'), '这是一段普通文本');
    });

    test('空字符串不变', () {
      expect(autoLinkUrls(''), '');
    });

    test('中文链接文字的 markdown 链接不变', () {
      expect(
        autoLinkUrls('[百度搜索](https://www.baidu.com)'),
        '[百度搜索](https://www.baidu.com)',
      );
    });

    test('多个 markdown 链接都不变', () {
      const input = '[A](https://a.com) 和 [B](https://b.com)';
      expect(autoLinkUrls(input), input);
    });

    test('markdown 链接 + 裸 URL 混合（AI 资讯实际格式）', () {
      const input = '**标题**\n摘要：xxx\n🔗 [https://ainews.com/p/xxx](https://ainews.com/p/xxx)\n\n**标题2**\n🔗 https://raw.example.com';
      const expected = '**标题**\n摘要：xxx\n🔗 [https://ainews.com/p/xxx](https://ainews.com/p/xxx)\n\n**标题2**\n🔗 [https://raw.example.com](https://raw.example.com)';
      expect(autoLinkUrls(input), expected);
    });

    test('角括号 <URL> autolink 转为 markdown 链接', () {
      expect(
        autoLinkUrls('项目地址 <https://github.com/NVIDIA/NemoClaw>'),
        '项目地址 [https://github.com/NVIDIA/NemoClaw](https://github.com/NVIDIA/NemoClaw)',
      );
    });

    test('多个角括号 <URL> 全部转换', () {
      const input = '链接1 <https://a.com> 链接2 <https://b.com>';
      expect(
        autoLinkUrls(input),
        '链接1 [https://a.com](https://a.com) 链接2 [https://b.com](https://b.com)',
      );
    });
  });
}
