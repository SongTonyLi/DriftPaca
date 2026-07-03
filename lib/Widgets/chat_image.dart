import 'package:flutter/material.dart';

class ChatImage extends StatelessWidget {
  final ImageProvider image;
  final double aspectRatio;
  final double? height;
  final double? width;

  const ChatImage({
    super.key,
    required this.image,
    this.aspectRatio = 1.0,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    // Cap the decode resolution to the display size so a large source image
    // (e.g. a 4032x3024 phone photo) is not decoded at full native resolution
    // into the image cache just to be painted as a small thumbnail. Only the
    // dimension we actually know (width or height) is capped; the other is left
    // null so the decoder preserves the source's aspect ratio instead of
    // stretching it. BoxFit.cover then crops as needed at paint time.
    //
    // The default `Image(...)` constructor takes a ready `ImageProvider` and
    // exposes no cacheWidth/cacheHeight, so we apply the cap by wrapping the
    // provider in `ResizeImage` ourselves via `resizeIfNeeded` -- the exact
    // helper `Image.file`/`Image.network` use to honour those parameters.
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth =
        width != null ? (width! * devicePixelRatio).round() : null;
    final cacheHeight = width == null && height != null
        ? (height! * devicePixelRatio).round()
        : null;
    final decodedImage =
        ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, image);

    return SizedBox(
      height: height,
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Image(
            image: decodedImage,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Icon(Icons.error, color: Colors.red),
              );
            },
          ),
        ),
      ),
    );
  }
}
