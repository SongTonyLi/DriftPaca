import 'dart:io';

import 'package:flutter/material.dart';
import 'package:llamaseek/Widgets/chat_image.dart';

class ChatAttachmentImage extends StatelessWidget {
  static const double previewHeightFactor = 0.15;

  final File imageFile;
  final Function(File) onRemove;

  const ChatAttachmentImage({
    super.key,
    required this.imageFile,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ChatImage(
          image: FileImage(imageFile),
          aspectRatio: 1.5,
          height: MediaQuery.of(context).size.height * previewHeightFactor,
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: () => onRemove(imageFile),
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  shadows: [BoxShadow(blurRadius: 10)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
