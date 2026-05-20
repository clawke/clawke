import 'package:flutter/material.dart';

class CopyableText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final String? semanticsLabel;

  const CopyableText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
    );
  }
}
