import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';

/// Renders streaming markdown without re-parsing the whole document per token.
///
/// The document is split into blocks (fenced code vs prose) and every built
/// block is cached by its exact content. While a stream is running only the
/// final block's content changes, so each incoming token rebuilds exactly one
/// widget instead of the entire answer — the difference between a smooth
/// teleprompter and a stuttering one at 60 tokens/second.
class StreamingMarkdown extends StatefulWidget {
  const StreamingMarkdown({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.onCopyCode,
  });

  /// The growing answer body.
  final ValueListenable<String> text;

  /// Draws the caret after the last glyph.
  final bool isStreaming;

  final void Function(String code)? onCopyCode;

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<StreamingMarkdown> {
  final Map<String, Widget> _cache = <String, Widget>{};
  String _previous = '';

  @override
  void didUpdateWidget(StreamingMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _cache.clear();
  }

  @override
  void dispose() {
    _cache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.text,
      builder: (BuildContext context, String markdown, _) {
        // A shorter body means a new turn started — drop the stale cache so it
        // cannot grow without bound across a long session.
        if (markdown.length < _previous.length) _cache.clear();
        _previous = markdown;

        final List<_Block> blocks = _parseBlocks(markdown);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < blocks.length; i++)
              _buildCached(blocks[i], isLast: i == blocks.length - 1),
          ],
        );
      },
    );
  }

  Widget _buildCached(_Block block, {required bool isLast}) {
    final bool showCaret = widget.isStreaming && isLast;
    final String key = '${block.cacheKey}|caret=$showCaret';

    final Widget? hit = _cache[key];
    if (hit != null) return hit;

    final Widget built = switch (block) {
      _CodeBlock() => _CodeBlockView(block: block, onCopy: widget.onCopyCode),
      _ProseBlock() => _ProseBlockView(block: block, showCaret: showCaret),
    };

    // Only the tail of a stream churns; cap the cache so a very long answer
    // cannot retain every intermediate state of its final block.
    if (_cache.length > 64) _cache.clear();
    _cache[key] = built;
    return built;
  }
}

// ---------------------------------------------------------------------------
// Block model + parser
// ---------------------------------------------------------------------------

sealed class _Block {
  const _Block();
  String get cacheKey;
}

class _ProseBlock extends _Block {
  const _ProseBlock(this.markdown, {this.emphasised = false});

  final String markdown;

  /// True for the body of the "Verbal Summary" section — the line the user
  /// reads out loud, set larger and brighter than everything else.
  final bool emphasised;

  @override
  String get cacheKey => 'p${emphasised ? 1 : 0}:$markdown';
}

class _CodeBlock extends _Block {
  const _CodeBlock(this.code, this.language, {this.isComplete = true});

  final String code;
  final String language;
  final bool isComplete;

  @override
  String get cacheKey => 'c:$language:${isComplete ? 1 : 0}:$code';
}

/// Splits markdown into prose and fenced-code blocks, tracking which section
/// each prose run belongs to.
///
/// Handles a trailing unterminated fence, which is the normal state of a code
/// block that is still streaming in.
List<_Block> _parseBlocks(String markdown) {
  if (markdown.isEmpty) return const <_Block>[];

  final List<_Block> blocks = <_Block>[];
  final List<String> lines = markdown.split('\n');

  final StringBuffer prose = StringBuffer();
  final StringBuffer code = StringBuffer();
  bool inCode = false;
  String language = '';
  bool verbalSection = false;

  void flushProse() {
    final String content = prose.toString().trimRight();
    prose.clear();
    if (content.trim().isEmpty) return;
    blocks.add(_ProseBlock(content, emphasised: verbalSection));
  }

  for (final String line in lines) {
    final String trimmed = line.trimLeft();

    if (trimmed.startsWith('```')) {
      if (inCode) {
        blocks.add(_CodeBlock(code.toString().trimRight(), language));
        code.clear();
        inCode = false;
        language = '';
      } else {
        flushProse();
        inCode = true;
        language = trimmed.substring(3).trim().toLowerCase();
      }
      continue;
    }

    if (inCode) {
      code.writeln(line);
      continue;
    }

    // A heading ends the previous prose run and re-evaluates emphasis.
    if (trimmed.startsWith('#')) {
      flushProse();
      final String headingText = trimmed
          .replaceFirst(RegExp(r'^#+\s*'), '')
          .toLowerCase();
      blocks.add(_ProseBlock(trimmed));
      verbalSection = headingText.contains('verbal');
      continue;
    }

    prose.writeln(line);
  }

  if (inCode) {
    // Still streaming inside a fence.
    blocks.add(
      _CodeBlock(code.toString().trimRight(), language, isComplete: false),
    );
  } else {
    flushProse();
  }

  return blocks;
}

// ---------------------------------------------------------------------------
// Prose
// ---------------------------------------------------------------------------

class _ProseBlockView extends StatelessWidget {
  const _ProseBlockView({required this.block, required this.showCaret});

  final _ProseBlock block;
  final bool showCaret;

  @override
  Widget build(BuildContext context) {
    final Widget body = MarkdownBody(
      data: showCaret ? '${block.markdown}▌' : block.markdown,
      selectable: false,
      shrinkWrap: true,
      fitContent: true,
      styleSheet: _styleSheetFor(block.emphasised),
      onTapLink: (_, String? href, _) {
        if (href != null) Clipboard.setData(ClipboardData(text: href));
      },
    );

    return Padding(padding: const EdgeInsets.only(bottom: 2), child: body);
  }

  MarkdownStyleSheet _styleSheetFor(bool emphasised) {
    final TextStyle base = emphasised ? XpType.verbal : XpType.body;

    return MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: XpType.title.copyWith(fontSize: 17),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h2: XpType.sectionHeading,
      h2Padding: const EdgeInsets.only(top: 12, bottom: 4),
      h3: XpType.sectionHeading.copyWith(color: XpColors.textSecondary),
      h3Padding: const EdgeInsets.only(top: 10, bottom: 2),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base.copyWith(color: XpColors.accentHover),
      listIndent: 18,
      blockSpacing: 6,
      code: XpType.codeInline,
      codeblockDecoration: const BoxDecoration(color: Colors.transparent),
      blockquote: XpType.bodyMuted.copyWith(fontStyle: FontStyle.italic),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: XpColors.accent, width: 2)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: XpColors.border)),
      ),
      a: base.copyWith(
        color: XpColors.accentHover,
        decoration: TextDecoration.underline,
      ),
      tableHead: XpType.label.copyWith(color: XpColors.textPrimary),
      tableBody: XpType.bodyMuted,
      tableBorder: TableBorder.all(color: XpColors.border, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

// ---------------------------------------------------------------------------
// Code
// ---------------------------------------------------------------------------

class _CodeBlockView extends StatefulWidget {
  const _CodeBlockView({required this.block, this.onCopy});

  final _CodeBlock block;
  final void Function(String code)? onCopy;

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.block.code));
    widget.onCopy?.call(widget.block.code);
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final String language = _normaliseLanguage(widget.block.language);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: XpColors.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: XpColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Header: language label + copy.
          Container(
            height: 28,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: XpColors.border)),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  widget.block.language.isEmpty
                      ? 'CODE'
                      : widget.block.language.toUpperCase(),
                  style: XpType.label.copyWith(letterSpacing: 1),
                ),
                if (!widget.block.isComplete) ...<Widget>[
                  const SizedBox(width: 8),
                  const _StreamingPulse(),
                ],
                const Spacer(),
                _CopyButton(copied: _copied, onTap: _copy),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: SelectionArea(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: HighlightView(
                  widget.block.code.isEmpty ? ' ' : widget.block.code,
                  language: language,
                  theme: _xpassHighlightTheme,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: XpType.code,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.copied, required this.onTap});

  final bool copied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy code',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 12,
                color: copied ? XpColors.statusLive : XpColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                copied ? 'Copied' : 'Copy',
                style: XpType.label.copyWith(
                  color: copied ? XpColors.statusLive : XpColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small breathing dot shown while a code block is still arriving.
class _StreamingPulse extends StatefulWidget {
  const _StreamingPulse();

  @override
  State<_StreamingPulse> createState() => _StreamingPulseState();
}

class _StreamingPulseState extends State<_StreamingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
      child: Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: XpColors.accentHover,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Syntax theme
// ---------------------------------------------------------------------------

/// highlight.js token theme in the xpass palette.
const Map<String, TextStyle> _xpassHighlightTheme = <String, TextStyle>{
  'root': TextStyle(
    color: XpColors.textPrimary,
    backgroundColor: Colors.transparent,
  ),
  'comment': TextStyle(
    color: XpColors.textTertiary,
    fontStyle: FontStyle.italic,
  ),
  'quote': TextStyle(color: XpColors.textTertiary, fontStyle: FontStyle.italic),
  'keyword': TextStyle(color: Color(0xFF7C9CF5), fontWeight: FontWeight.w600),
  'selector-tag': TextStyle(color: Color(0xFF7C9CF5)),
  'literal': TextStyle(color: Color(0xFFF59E0B)),
  'type': TextStyle(color: Color(0xFF5EEAD4)),
  'built_in': TextStyle(color: Color(0xFF5EEAD4)),
  'class': TextStyle(color: Color(0xFF5EEAD4)),
  'title': TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w600),
  'function': TextStyle(color: Color(0xFF93C5FD)),
  'params': TextStyle(color: XpColors.textPrimary),
  'string': TextStyle(color: Color(0xFF86EFAC)),
  'number': TextStyle(color: Color(0xFFF59E0B)),
  'symbol': TextStyle(color: Color(0xFFF59E0B)),
  'bullet': TextStyle(color: Color(0xFFF59E0B)),
  'attr': TextStyle(color: Color(0xFFC4B5FD)),
  'attribute': TextStyle(color: Color(0xFFC4B5FD)),
  'variable': TextStyle(color: XpColors.textPrimary),
  'template-variable': TextStyle(color: Color(0xFFC4B5FD)),
  'meta': TextStyle(color: XpColors.textTertiary),
  'meta-keyword': TextStyle(color: Color(0xFF7C9CF5)),
  'regexp': TextStyle(color: Color(0xFF86EFAC)),
  'link': TextStyle(color: XpColors.accentHover),
  'selector-id': TextStyle(color: Color(0xFFF87171)),
  'selector-class': TextStyle(color: Color(0xFFC4B5FD)),
  'tag': TextStyle(color: Color(0xFF7C9CF5)),
  'name': TextStyle(color: Color(0xFF7C9CF5)),
  'deletion': TextStyle(color: Color(0xFFF87171)),
  'addition': TextStyle(color: Color(0xFF86EFAC)),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.bold),
};

/// Maps the language labels we show users onto highlight.js identifiers.
String _normaliseLanguage(String raw) {
  final String value = raw.trim().toLowerCase();
  return switch (value) {
    '' || 'text' || 'plaintext' || 'txt' => 'plaintext',
    'py' || 'python3' => 'python',
    'ts' || 'tsx' => 'typescript',
    'js' || 'jsx' || 'node' => 'javascript',
    'c++' || 'cc' || 'cxx' || 'c' => 'cpp',
    'c#' || 'cs' => 'csharp',
    'golang' => 'go',
    'rs' => 'rust',
    'kt' => 'kotlin',
    'rb' => 'ruby',
    'sh' || 'zsh' || 'bash' => 'bash',
    'yml' => 'yaml',
    _ => value,
  };
}
