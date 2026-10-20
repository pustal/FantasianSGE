/// Decorative pieces that give the app its FANTASIAN-like feel: a starry
/// night backdrop, gold ornaments and the brand header.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Paints the page background: a night sky with scattered stars in dark mode,
/// warm parchment with a soft vignette in light mode.
class SkyBackground extends StatelessWidget {
  /// Wraps [child] with the background.
  const SkyBackground({required this.child, super.key});

  /// The page content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // SizedBox.expand so the sky fills the page even when content is short.
    return SizedBox.expand(
      child: CustomPaint(
        painter: _SkyPainter(
          dark: scheme.brightness == Brightness.dark,
          base: scheme.surface,
          glow: scheme.surfaceContainerHigh,
          star: scheme.primary,
        ),
        child: child,
      ),
    );
  }
}

/// Draws the gradient and a fixed, seeded scatter of stars.
class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.dark,
    required this.base,
    required this.glow,
    required this.star,
  });

  final bool dark;
  final Color base;
  final Color glow;
  final Color star;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.6, -0.9),
          radius: 1.4,
          colors: <Color>[glow, base],
        ).createShader(rect),
    );
    if (!dark) {
      return;
    }
    // Seeded so the stars do not jump around on every repaint.
    final math.Random random = math.Random(7);
    final Paint paint = Paint();
    final int count = (size.width * size.height / 9000).clamp(20, 220).round();
    for (int i = 0; i < count; i++) {
      final Offset at = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
      final double radius = random.nextDouble() * 1.3 + 0.3;
      paint.color = star.withValues(alpha: random.nextDouble() * 0.45 + 0.1);
      canvas.drawCircle(at, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.base != base || oldDelegate.star != star;
}

/// A thin gold rule with a diamond in the middle.
class OrnamentDivider extends StatelessWidget {
  /// Creates the divider.
  const OrnamentDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);
    Widget line() => Expanded(child: Container(height: 1, color: color));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 8, height: 8, color: color),
            ),
          ),
          line(),
        ],
      ),
    );
  }
}

/// The logo with the app's name and tagline.
class BrandHeader extends StatelessWidget {
  /// Creates the header; [compact] shows only the logo and name.
  const BrandHeader({this.compact = false, super.key});

  /// Whether to use the small, single-line layout.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget logo = Image.asset(
      'assets/brand/logo.png',
      width: compact ? 40 : 96,
      height: compact ? 40 : 96,
      semanticLabel: '${AppInfo.name} logo',
    );
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          logo,
          const SizedBox(width: 10),
          Text(AppInfo.name, style: theme.textTheme.titleLarge),
        ],
      );
    }
    return Column(
      children: <Widget>[
        logo,
        const SizedBox(height: 8),
        Text(AppInfo.name, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 2),
        Text(
          'FANTASIAN Save Game Extractor',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
