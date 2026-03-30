import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'fx_icon_button.dart';

class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    this.onShare,
    this.isExporting = false,
    this.exportProgress = 0,
  });

  final VoidCallback? onShare;
  final bool isExporting;
  final double exportProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: FxPalette.background,
        border: Border(
          bottom: BorderSide(color: FxPalette.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          const FxIconButton(
            icon: Icons.history_rounded,
            size: 34,
            iconScale: 0.38,
          ),
          const SizedBox(width: 6),
          const FxIconButton(
              icon: Icons.undo_rounded, size: 34, iconScale: 0.38),
          const SizedBox(width: 6),
          const FxIconButton(
              icon: Icons.redo_rounded, size: 34, iconScale: 0.38),
          const Spacer(),
          Stack(
            alignment: Alignment.center,
            children: [
              FxIconButton(
                icon: Icons.ios_share_rounded,
                size: 34,
                iconScale: 0.38,
                onPressed: isExporting ? null : onShare,
              ),
              if (isExporting)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: exportProgress <= 0 || exportProgress >= 1
                        ? null
                        : exportProgress,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      FxPalette.accent,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
