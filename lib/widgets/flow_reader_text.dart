import 'dart:ui' show TextBox;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../core/app_colors.dart';
import '../core/script_matcher.dart';

/// Layout estático. O cursor muda exclusivamente a pintura.
class FlowReaderText extends LeafRenderObjectWidget {
  const FlowReaderText({
    super.key, required this.text, required this.words,
    required this.style, required this.highlight,
  });

  final String text;
  final List<ScriptWord> words;
  final TextStyle style;
  final ValueNotifier<int> highlight;

  @override
  FlowReaderRender createRenderObject(BuildContext context) => FlowReaderRender(
    text: text, words: words, style: style, highlight: highlight,
    direction: Directionality.of(context), scaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, FlowReaderRender renderObject) {
    renderObject.update(
      text: text, words: words, style: style, highlight: highlight,
      direction: Directionality.of(context), scaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
  }
}

class FlowReaderRender extends RenderBox {
  FlowReaderRender({
    required String text, required List<ScriptWord> words, required TextStyle style,
    required ValueNotifier<int> highlight, required TextDirection direction,
    required TextScaler scaler, required Locale? locale,
  }) : _text = text, _words = words, _style = style, _highlight = highlight,
       _direction = direction, _scaler = scaler, _locale = locale {
    _configurePainters();
  }

  String _text;
  List<ScriptWord> _words;
  TextStyle _style;
  ValueNotifier<int> _highlight;
  TextDirection _direction;
  TextScaler _scaler;
  Locale? _locale;
  final _white = TextPainter();
  final _dim = TextPainter();
  final _active = TextPainter();

  void _configurePainters() {
    for (final entry in [
      (_white, Colors.white), (_dim, const Color(0xFF777777)),
      (_active, AppColors.onBrand),
    ]) {
      final painter = entry.$1;
      painter
        ..text = TextSpan(text: _text, style: _style.copyWith(color: entry.$2))
        ..textAlign = TextAlign.center
        ..textDirection = _direction
        ..textScaler = _scaler
        ..locale = _locale;
    }
  }

  void update({
    required String text, required List<ScriptWord> words, required TextStyle style,
    required ValueNotifier<int> highlight, required TextDirection direction,
    required TextScaler scaler, required Locale? locale,
  }) {
    if (!identical(_highlight, highlight)) {
      if (attached) _highlight.removeListener(_highlightChanged);
      _highlight = highlight;
      if (attached) _highlight.addListener(_highlightChanged);
      markNeedsPaint();
    }
    if (_text == text && identical(_words, words) && _style == style &&
        _direction == direction && _scaler == scaler && _locale == locale) return;
    _text = text;
    _words = words;
    _style = style;
    _direction = direction;
    _scaler = scaler;
    _locale = locale;
    _configurePainters();
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  void _highlightChanged() => markNeedsPaint();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _highlight.addListener(_highlightChanged);
  }

  @override
  void detach() {
    _highlight.removeListener(_highlightChanged);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout() {
    // O leitor está em um scroll vertical com largura delimitada.
    for (final painter in [_white, _dim, _active]) {
      painter.layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    }
    size = constraints.constrain(Size(_white.width, _white.height));
  }

  List<TextBox> getBoxesForSelection(TextSelection selection) =>
      _white.getBoxesForSelection(selection);

  TextPosition getPositionForOffset(Offset offset) => _white.getPositionForOffset(offset);

  Path _pathFor(int start, int end) {
    final path = Path();
    if (end <= start) return path;
    for (final box in getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))) {
      path.addRect(box.toRect());
    }
    return path;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final index = _highlight.value;
    if (index < 0 || index >= _words.length) {
      _white.paint(canvas, offset);
      return;
    }
    final word = _words[index];
    final read = _pathFor(0, word.start);
    final active = _pathFor(word.start, word.end);
    final remainder = Path.combine(PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path.combine(PathOperation.union, read, active));
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawPath(active, Paint()..color = AppColors.brand);
    void draw(TextPainter painter, Path clip) {
      canvas.save();
      canvas.clipPath(clip, doAntiAlias: false);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
    draw(_white, remainder);
    draw(_dim, read);
    draw(_active, active);
    canvas.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.label = _text;
    config.textDirection = _direction;
  }

  @override
  void dispose() {
    _white.dispose();
    _dim.dispose();
    _active.dispose();
    super.dispose();
  }
}
