import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

/// Extension on [BuildContext] to provide consistent markdown styling across the app.
extension MarkdownStyleSheetExtension on BuildContext {
  /// Returns a [MarkdownStyleSheet] that matches the app's theme with bodyLarge text size,
  /// properly styled code blocks and inline code.
  MarkdownStyleSheet get markdownStyleSheet {
    final theme = Theme.of(this);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Code block colors — soft gray, readable in both themes
    final codeBlockBg = isDark
        ? colorScheme.surfaceContainerHighest
        : const Color(0xFFF3F4F6);
    final codeTextColor = isDark
        ? colorScheme.onSurface
        : const Color(0xFF374151);

    // Inline code colors — subtle background
    final inlineCodeBg = colorScheme.onSurface.withValues(alpha: 0.07);
    final inlineCodeColor = colorScheme.onSurface;

    final codeFont = GoogleFonts.jetBrainsMono(
      fontSize: 13,
      color: inlineCodeColor,
      backgroundColor: inlineCodeBg,
    );

    final codeBlockFont = GoogleFonts.jetBrainsMono(
      fontSize: 12.5,
      height: 1.5,
      color: codeTextColor,
    );

    return MarkdownStyleSheet.fromTheme(
      theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            height: 1.65,
          ),
        ),
      ),
    ).copyWith(
      textScaler: MediaQuery.textScalerOf(this).clamp(
        minScaleFactor: 0.8,
        maxScaleFactor: 2.0,
      ),
      // Headings — proportional to 15px body, not oversized
      h1: theme.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h2: theme.textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h3: theme.textTheme.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h4: theme.textTheme.bodyLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.5,
      ),
      h1Padding: const EdgeInsets.only(top: 8),
      h2Padding: const EdgeInsets.only(top: 6),
      h3Padding: const EdgeInsets.only(top: 10),
      h4Padding: const EdgeInsets.only(top: 8),
      // Block spacing between paragraphs
      blockSpacing: 12,
      // Blockquote — sky-blue left border with rounded right corners
      blockquoteDecoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1A3A4A) : const Color(0xFFE8F4FD)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        border: Border(
          left: BorderSide(
            width: 2.5,
            color: const Color(0xFF7EC8E3),
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      // Thin horizontal rule like reference app
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            width: 0.5,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      // Inline code
      code: codeFont,
      // Code blocks
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(10),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockAlign: WrapAlignment.start,
      // Tables — intrinsic width enables horizontal scroll for wide tables
      tableColumnWidth: const IntrinsicColumnWidth(),
      textAlign: WrapAlignment.spaceBetween, // → TextAlign.justify for paragraphs
    );
  }
}
