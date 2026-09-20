import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

/// Detects whether a string contains LaTeX or mathematical equation syntax.
bool _looksLikeMath(String text) {
  if (text.isEmpty) return false;
  final clean = text.trim();

  // Typical LaTeX math commands and symbols
  final mathCommands = RegExp(
    r'\\(sin|cos|tan|cot|sec|csc|pi|times|frac|sqrt|text|pm|cdot|omega|theta|lambda|alpha|beta|gamma|delta|Delta|approx|neq|le|ge|sum|int|partial|degree|infty|mu|sigma|rho|phi|psi|left|right|vec|hat|bar|to|cup|cap|in|notin|forall|exists|nabla)\b',
  );
  if (mathCommands.hasMatch(clean)) return true;

  // Equation patterns containing variables, operators and mathematical notation
  if (clean.contains('=') &&
      (clean.contains(r'\') ||
          clean.contains('^') ||
          clean.contains('_') ||
          clean.contains('(') ||
          clean.contains(')'))) {
    // Exclude programming code statements like `int x = 5;` or `var a = ...`
    if (!clean.contains(';') &&
        !clean.contains('var ') &&
        !clean.contains('final ') &&
        !clean.contains('let ') &&
        !clean.contains('const ') &&
        !clean.contains('def ')) {
      return true;
    }
  }

  return false;
}

/// Cleans raw math text for robust rendering with flutter_math_fork.
String _sanitizeMath(String raw) {
  var s = raw.trim();
  s = s.replaceAll('\u00A0', ' ');

  // Strip wrapping delimiters if present
  if (s.startsWith(r'$$') && s.endsWith(r'$$') && s.length >= 4) {
    s = s.substring(2, s.length - 2).trim();
  } else if (s.startsWith(r'\[') && s.endsWith(r'\]') && s.length >= 4) {
    s = s.substring(2, s.length - 2).trim();
  } else if (s.startsWith(r'\(') && s.endsWith(r'\)') && s.length >= 4) {
    s = s.substring(2, s.length - 2).trim();
  } else if (s.startsWith(r'$') && s.endsWith(r'$') && s.length >= 2) {
    s = s.substring(1, s.length - 1).trim();
  }

  return s;
}

/// A syntax for parsing display math expressions: `$$...$$` or `\[...\]`.
class _DisplayMathSyntax extends md.InlineSyntax {
  _DisplayMathSyntax() : super(r'\$\$(.+?)\$\$|\\\[(.+?)\\\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = (match.group(1) ?? match.group(2) ?? '').trim();
    final element = md.Element('displaymath', [md.Text(formula)]);
    parser.addNode(element);
    return true;
  }
}

/// A syntax for parsing inline math expressions: `$x = 5$` or `\(...\)`.
class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax()
      : super(r'(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)|\\\((.+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = (match.group(1) ?? match.group(2) ?? '').trim();
    final element = md.Element('inlinemath', [md.Text(formula)]);
    parser.addNode(element);
    return true;
  }
}

/// Renders inline math formulas using `flutter_math_fork`.
class _InlineMathElementBuilder extends MarkdownElementBuilder {
  _InlineMathElementBuilder({this.textStyle});
  final TextStyle? textStyle;

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final mathText = _sanitizeMath(element.textContent.trim());
    return Math.tex(
      mathText,
      mathStyle: MathStyle.text,
      textStyle: preferredStyle ?? textStyle,
      onErrorFallback: (err) => Text('\$$mathText\$', style: preferredStyle),
    );
  }
}

/// Renders display/block math formulas as centered, beautifully-styled cards.
class _DisplayMathElementBuilder extends MarkdownElementBuilder {
  _DisplayMathElementBuilder({required this.theme});
  final ThemeData theme;

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final sanitizedMath = _sanitizeMath(element.textContent.trim());
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          sanitizedMath,
          mathStyle: MathStyle.display,
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          onErrorFallback: (err) => Text(
            sanitizedMath,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders code blocks (e.g. fenced programming code or explicit math blocks).
class _CodeBlockElementBuilder extends MarkdownElementBuilder {
  _CodeBlockElementBuilder({required this.theme});
  final ThemeData theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    // Required by flutter_markdown for block element builders to avoid assertion crashes
    return const SizedBox.shrink();
  }

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.trim();
    final className = element.attributes['class'] ?? '';
    final isExplicitMath =
        className == 'language-math' ||
        className == 'language-latex' ||
        className == 'language-tex';
    final isMath = isExplicitMath || _looksLikeMath(code);

    if (isMath) {
      final sanitizedMath = _sanitizeMath(code);
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            sanitizedMath,
            mathStyle: MathStyle.display,
            textStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
            onErrorFallback: (err) => Text(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }

    // Default code blocks for regular programming code
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.65,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: SelectableText(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// A rich, pedagogical Markdown and LaTeX Math renderer for Leyli AI tutor responses.
class RichTutorMarkdown extends StatelessWidget {
  const RichTutorMarkdown({super.key, required this.text, this.isUser = false});

  final String text;
  final bool isUser;

  static String preprocess(String raw) {
    var processed = raw;

    // 1. Normalize headings with spaced hashes e.g. '# # #' or '#  #  #' -> '### '
    processed = processed.replaceAllMapped(
      RegExp(r'(^|\n)\s*#(?:\s*#)+\s*([^\n]+)'),
      (match) {
        final prefix = match.group(1) ?? '';
        final text = match.group(2)?.trim() ?? '';
        return '$prefix\n\n### $text\n\n';
      },
    );

    // 2. Ensure all Markdown headings (### Heading) have double newlines before them
    processed = processed.replaceAllMapped(
      RegExp(r'([^\n])\n(#{1,6}[\t\u00A0 ]+[^\n]+)'),
      (match) => '${match.group(1)}\n\n${match.group(2)}',
    );

    // 3. Ensure horizontal rules (---, ***, ___) have adequate spacing
    processed = processed.replaceAllMapped(
      RegExp(r'([^\n])\n([ \t]*[-*_]{3,}[ \t]*)(\n|$)'),
      (match) => '${match.group(1)}\n\n${match.group(2)}\n\n',
    );
    processed = processed.replaceAllMapped(
      RegExp(r'(^|\n)([ \t]*[-*_]{3,}[ \t]*)\n([^\n])'),
      (match) => '${match.group(1)}${match.group(2)}\n\n${match.group(3)}',
    );

    return processed.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final processedData = preprocess(text);

    final textColor = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    final baseStyle = GoogleFonts.plusJakartaSans(
      fontSize: 14.5,
      height: 1.55,
      color: textColor,
    );

    final markdownStyle = MarkdownStyleSheet(
      p: baseStyle,
      h1: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: isUser ? textColor : const Color(0xFF000000),
        height: 1.3,
      ),
      h1Padding: const EdgeInsets.only(top: 14, bottom: 6),
      h2: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isUser ? textColor : const Color(0xFF000000),
        height: 1.3,
      ),
      h2Padding: const EdgeInsets.only(top: 12, bottom: 6),
      h3: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: isUser ? textColor : theme.colorScheme.onSurface,
        height: 1.35,
      ),
      h3Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h4: GoogleFonts.plusJakartaSans(
        fontSize: 14.5,
        fontWeight: FontWeight.bold,
        color: isUser ? textColor : theme.colorScheme.onSurface,
        height: 1.35,
      ),
      h4Padding: const EdgeInsets.only(top: 8, bottom: 4),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      listBullet: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: isUser ? textColor : const Color(0xFF000000),
      ),
      listBulletPadding: const EdgeInsets.only(right: 6),
      listIndent: 20,
      blockquote: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontStyle: FontStyle.italic,
        height: 1.5,
        color: isUser ? textColor : theme.colorScheme.onSurfaceVariant,
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3.5),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            width: 1.2,
          ),
        ),
      ),
      code: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        color: isUser ? textColor : const Color(0xFF000000),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      tableBorder: TableBorder.all(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        width: 1,
        borderRadius: BorderRadius.circular(8),
      ),
      tableHead: const TextStyle(fontWeight: FontWeight.bold),
      tablePadding: const EdgeInsets.all(8),
    );

    return MarkdownBody(
      data: processedData,
      selectable: true,
      styleSheet: markdownStyle,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [
        _DisplayMathSyntax(),
        _InlineMathSyntax(),
      ],
      builders: {
        'displaymath': _DisplayMathElementBuilder(theme: theme),
        'inlinemath': _InlineMathElementBuilder(textStyle: baseStyle),
        'math': _InlineMathElementBuilder(textStyle: baseStyle),
        'pre': _CodeBlockElementBuilder(theme: theme),
      },
    );
  }
}
