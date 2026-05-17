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
          height: MediaQuery.of(context).size.height * previewHeightFactor,
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: () => onRemove(imageFile),
            child: Icon(
              Icons.close,
              color: Colors.white,
              shadows: [BoxShadow(blurRadius: 10)],
            ),
          ),
        ),
      ],
    );
  }
}
