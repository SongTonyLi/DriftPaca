import 'package:flutter/material.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/streaming_llama.dart';
import 'package:llamaseek/Widgets/flexible_text.dart';

class OllamaBottomSheetHeader extends StatelessWidget {
  final String title;

  const OllamaBottomSheetHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: StreamingLlama(isRunning: false),
        ),
        FlexibleText(
          title,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
