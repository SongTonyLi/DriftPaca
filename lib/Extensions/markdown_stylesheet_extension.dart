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
          bodyMedium: theme.textTheme.bodyLarge,
        ),
      ),
    ).copyWith(
      textScaler: MediaQuery.textScalerOf(this).clamp(
        minScaleFactor: 0.8,
        maxScaleFactor: 2.0,
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
    );
  }
}
