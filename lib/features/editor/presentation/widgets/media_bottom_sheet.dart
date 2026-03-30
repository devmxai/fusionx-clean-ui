import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../models/device_media_item.dart';
import '../models/editor_media_tab.dart';

class MediaBottomSheet extends StatelessWidget {
  const MediaBottomSheet({
    super.key,
    required this.activeTab,
    required this.mediaItems,
    required this.selectedMediaId,
    required this.isLoading,
    required this.errorMessage,
    required this.onTabChanged,
    required this.onMediaSelected,
    required this.onImport,
    required this.thumbnailLoader,
    required this.importEnabled,
    this.importHint,
  });

  final EditorMediaTab activeTab;
  final List<DeviceMediaItem> mediaItems;
  final String? selectedMediaId;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<EditorMediaTab> onTabChanged;
  final ValueChanged<DeviceMediaItem> onMediaSelected;
  final Future<void> Function() onImport;
  final Future<Uint8List?> Function(DeviceMediaItem item) thumbnailLoader;
  final bool importEnabled;
  final String? importHint;

  static const List<EditorMediaTab> _tabs = <EditorMediaTab>[
    EditorMediaTab.video,
    EditorMediaTab.image,
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.66,
      minChildSize: 0.44,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: FxPalette.panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: FxPalette.divider, width: 1),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  children: [
                    for (final tab in _tabs) ...[
                      Expanded(
                        child: _SheetTabButton(
                          tab: tab,
                          isActive: tab == activeTab,
                          onTap: () => onTabChanged(tab),
                        ),
                      ),
                      if (tab != _tabs.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _buildBody(controller),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                decoration: BoxDecoration(
                  color: FxPalette.panel,
                  border: Border(
                    top: BorderSide(
                      color: FxPalette.dividerSoft.withOpacity(0.9),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (importHint != null) ...[
                      Text(
                        importHint!,
                        style: const TextStyle(
                          color: FxPalette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: importEnabled
                            ? () async {
                                await onImport();
                              }
                            : null,
                        child: const Text('Import'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController controller) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: FxPalette.accent,
        ),
      );
    }

    if (errorMessage != null) {
      return _StateMessage(
        icon: Icons.warning_amber_rounded,
        title: 'Media access issue',
        body: errorMessage!,
      );
    }

    if (mediaItems.isEmpty) {
      return _StateMessage(
        icon: activeTab.icon,
        title: activeTab == EditorMediaTab.video
            ? 'No videos found'
            : 'No images found',
        body: activeTab == EditorMediaTab.video
            ? 'No videos are currently available through the Android media library.'
            : 'No images are currently available through the Android media library.',
      );
    }

    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: mediaItems.length,
      itemBuilder: (context, index) {
        final item = mediaItems[index];
        return _MediaSelectionTile(
          item: item,
          isSelected: item.id == selectedMediaId,
          thumbnailLoader: thumbnailLoader,
          onTap: () => onMediaSelected(item),
        );
      },
    );
  }
}

class _SheetTabButton extends StatelessWidget {
  const _SheetTabButton({
    required this.tab,
    required this.isActive,
    required this.onTap,
  });

  final EditorMediaTab tab;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isActive
                ? FxPalette.accent.withOpacity(0.12)
                : FxPalette.surface,
            border: Border.all(
              color: isActive ? FxPalette.accent : FxPalette.divider,
              width: 1,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tab.icon,
                  size: 16,
                  color: isActive ? FxPalette.textPrimary : FxPalette.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  tab.label,
                  style: TextStyle(
                    color:
                        isActive ? FxPalette.textPrimary : FxPalette.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaSelectionTile extends StatelessWidget {
  const _MediaSelectionTile({
    required this.item,
    required this.isSelected,
    required this.thumbnailLoader,
    required this.onTap,
  });

  final DeviceMediaItem item;
  final bool isSelected;
  final Future<Uint8List?> Function(DeviceMediaItem item) thumbnailLoader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? FxPalette.accent : FxPalette.divider,
              width: isSelected ? 1.5 : 1,
            ),
            color: FxPalette.surface,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: _MediaThumbnail(
                    item: item,
                    loader: thumbnailLoader,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: isSelected ? 1 : 0.85,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? FxPalette.accent : Colors.black54,
                      border: Border.all(
                        color: isSelected
                            ? FxPalette.accent
                            : Colors.white.withOpacity(0.22),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      isSelected ? Icons.check_rounded : Icons.circle_outlined,
                      size: 14,
                      color: isSelected ? Colors.black : FxPalette.textPrimary,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.78),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(17),
                    ),
                  ),
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FxPalette.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  const _MediaThumbnail({
    required this.item,
    required this.loader,
  });

  final DeviceMediaItem item;
  final Future<Uint8List?> Function(DeviceMediaItem item) loader;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loader(item),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                FxPalette.surfaceRaised,
                Colors.black.withOpacity(0.78),
              ],
            ),
          ),
          child: Center(
            child: Icon(
              item.tab == EditorMediaTab.video
                  ? Icons.videocam_rounded
                  : Icons.image_rounded,
              color: FxPalette.textMuted,
              size: 30,
            ),
          ),
        );
      },
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: FxPalette.textMuted,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: FxPalette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: FxPalette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
