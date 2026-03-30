import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class FxIconButton extends StatelessWidget {
  const FxIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 42,
    this.iconScale = 0.42,
    this.foregroundColor,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconScale;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: backgroundColor ?? FxPalette.surface,
          foregroundColor: foregroundColor ?? FxPalette.textMuted,
          side: const BorderSide(color: FxPalette.divider, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(size * 0.36),
          ),
        ),
        child: Icon(icon, size: size * iconScale),
      ),
    );
  }
}
