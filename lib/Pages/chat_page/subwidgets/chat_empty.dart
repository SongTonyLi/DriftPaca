import 'package:flutter/material.dart';
import 'package:llamaseek/Constants/constants.dart';

class ChatEmpty extends StatelessWidget {
  final Widget child;

  const ChatEmpty({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(AppConstants.appIconPng, height: 48),
            child,
          ],
        ),
      ),
    );
  }
}
