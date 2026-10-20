/// The common scrolling layout every tab uses.
library;

import 'package:flutter/material.dart';

import '../widgets/decor.dart';

/// A centred, width-limited, scrollable column with a page title.
class PageFrame extends StatelessWidget {
  /// Creates a page with [title], an [intro] paragraph and [children].
  const PageFrame({
    required this.title,
    required this.children,
    this.intro,
    super.key,
  });

  /// The page heading.
  final String title;

  /// A short paragraph under the heading.
  final String? intro;

  /// The page's sections, spaced evenly.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(title, style: theme.textTheme.headlineMedium),
                if (intro != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    intro!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const OrnamentDivider(),
                const SizedBox(height: 8),
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 16),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
