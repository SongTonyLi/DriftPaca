import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:llamaseek/Widgets/chat_image.dart';

class ChatBubbleImage extends StatelessWidget {
  final File imageFile;
  final List<File> allImages;
  final int index;

  const ChatBubbleImage({
    super.key,
    required this.imageFile,
    required this.allImages,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            pageBuilder: (context, animation, secondaryAnimation) {
              return _ImageGalleryFullScreen(
                images: allImages,
                initialIndex: index,
              );
            },
            transitionsBuilder: (context, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Hero(
        tag: imageFile.path,
        child: ChatImage(
          image: FileImage(imageFile),
          aspectRatio: 1.5,
          width: max(
            MediaQuery.of(context).size.width * 0.35,
            MediaQuery.of(context).size.height * 0.25,
          ),
        ),
      ),
    );
  }
}

class _ImageGalleryFullScreen extends StatefulWidget {
  final List<File> images;
  final int initialIndex;

  const _ImageGalleryFullScreen({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_ImageGalleryFullScreen> createState() =>
      _ImageGalleryFullScreenState();
}

class _ImageGalleryFullScreenState extends State<_ImageGalleryFullScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  late AnimationController _springController;
  late Animation<Offset> _springOffsetAnim;
  late Animation<double> _springScaleAnim;
  late Animation<double> _springOpacityAnim;

  Offset _dragOffset = Offset.zero;
  double _dragScale = 1.0;
  double _backgroundOpacity = 1.0;
  bool _isZoomed = false;
  late PhotoViewScaleStateController _scaleStateController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _scaleStateController = PhotoViewScaleStateController()
      ..outputScaleStateStream.listen(_onScaleStateChanged);
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        setState(() {
          _dragOffset = _springOffsetAnim.value;
          _dragScale = _springScaleAnim.value;
          _backgroundOpacity = _springOpacityAnim.value;
        });
      });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scaleStateController.dispose();
    _springController.dispose();
    super.dispose();
  }

  void _onScaleStateChanged(PhotoViewScaleState scaleState) {
    final zoomed = scaleState != PhotoViewScaleState.initial &&
        scaleState != PhotoViewScaleState.zoomedOut;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
        if (zoomed) {
          _dragOffset = Offset.zero;
          _dragScale = 1.0;
          _backgroundOpacity = 1.0;
        }
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _springController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += Offset(0, details.delta.dy);
      final distance = _dragOffset.dy.abs();
      _backgroundOpacity = (1.0 - distance / 400).clamp(0.2, 1.0);
      _dragScale = (1.0 - distance / 1200).clamp(0.8, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final distance = _dragOffset.dy.abs();

    if (distance > 100 || velocity.abs() > 800) {
      Navigator.pop(context);
    } else {
      _springOffsetAnim = Tween<Offset>(
        begin: _dragOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _springController,
        curve: Curves.easeOutCubic,
      ));
      _springScaleAnim = Tween<double>(
        begin: _dragScale,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _springController,
        curve: Curves.easeOutCubic,
      ));
      _springOpacityAnim = Tween<double>(
        begin: _backgroundOpacity,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _springController,
        curve: Curves.easeOutCubic,
      ));
      _springController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _backgroundOpacity),
      body: Stack(
        children: [
          // Gallery with dismiss transform
          Transform.translate(
            offset: _dragOffset,
            child: Transform.scale(
              scale: _dragScale,
              child: PhotoViewGallery.builder(
                pageController: _pageController,
                itemCount: widget.images.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _isZoomed = false;
                  });
                },
                builder: (context, index) {
                  return PhotoViewGalleryPageOptions(
                    imageProvider: FileImage(widget.images[index]),
                    heroAttributes: PhotoViewHeroAttributes(
                      tag: widget.images[index].path,
                    ),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    scaleStateController: index == _currentIndex
                        ? _scaleStateController
                        : null,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error, color: Colors.red),
                      );
                    },
                  );
                },
                backgroundDecoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
          // Vertical dismiss gesture layer (only when not zoomed)
          if (!_isZoomed)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
              ),
            ),
          // Close button
          Positioned(
            top: padding.top + 5,
            right: 0,
            child: Opacity(
              opacity: _backgroundOpacity,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  shadows: [BoxShadow(blurRadius: 10)],
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          // Image counter
          if (widget.images.length > 1)
            Positioned(
              top: padding.top + 12,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: _backgroundOpacity,
                child: Center(
                  child: Text(
                    '${_currentIndex + 1} / ${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      shadows: [BoxShadow(blurRadius: 10)],
                    ),
                  ),
                ),
              ),
            ),
          // Page indicator dots
          if (widget.images.length > 1)
            Positioned(
              bottom: padding.bottom + 20,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: _backgroundOpacity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.images.length, (index) {
                    final isActive = _currentIndex == index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 8 : 6,
                      height: isActive ? 8 : 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
