import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:llamaseek/Widgets/flexible_text.dart';

class ReinsSettings extends StatelessWidget {
  const ReinsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DriftPaca',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Privacy Policy'),
          subtitle: Text('How your data is handled'),
          onTap: () {
            launchUrlString('https://github.com/SongTonyLi/DriftPaca/blob/main/PRIVACY_POLICY.md');
          },
        ),
        ListTile(
          leading: Icon(Icons.code),
          title: Text('Go to Source Code'),
          subtitle: Text('View on GitHub'),
          onTap: () {
            launchUrlString('https://github.com/SongTonyLi/DriftPaca');
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 5,
          children: [
            Icon(Icons.favorite, color: Colors.red, size: 16),
            FlexibleText(
              "Thanks for using DriftPaca!",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }
}
