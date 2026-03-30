import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../models/editor_media_tab.dart';
import '../models/mock_asset_item.dart';
import '../models/timeline_mock_models.dart';
import '../widgets/editor_tools_bar.dart';
import '../widgets/editor_top_bar.dart';
import '../widgets/media_bottom_sheet.dart';
import '../widgets/media_dock.dart';
import '../widgets/preview_stage.dart';
import '../widgets/timeline_panel.dart';

class FusionXCleanUiScreen extends StatefulWidget {
  const FusionXCleanUiScreen({super.key});

  @override
  State<FusionXCleanUiScreen> createState() => _FusionXCleanUiScreenState();
}

class _FusionXCleanUiScreenState extends State<FusionXCleanUiScreen> {
  static const double _projectWidth = 1080;
  static const double _projectHeight = 1920;
  static const double _fps = 30;

  late final ValueNotifier<List<MockAssetItem>> _assetLibrary;
  EditorMediaTab _activeTab = EditorMediaTab.video;
  List<TimelineTrackData> _tracks = const <TimelineTrackData>[];
  String? _selectedClipId = 'clip-video-1';
  double _currentSeconds = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    _assetLibrary = ValueNotifier<List<MockAssetItem>>(_buildInitialAssets());
    _tracks = _buildInitialTracks();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _assetLibrary.dispose();
    super.dispose();
  }

  double get _workspaceAspectRatio => _projectWidth / _projectHeight;

  double get _timelineDuration {
    var maxDuration = 0.0;
    for (final track in _tracks) {
      var cursor = 0.0;
      for (final clip in track.clips) {
        cursor += clip.duration;
      }
      maxDuration = math.max(maxDuration, cursor);
    }
    return maxDuration <= 0 ? 14 : maxDuration;
  }

  MockAssetItem? get _selectedAsset {
    final selectedClipId = _selectedClipId;
    if (selectedClipId == null) {
      return null;
    }
    String? assetId;
    for (final track in _tracks) {
      for (final clip in track.clips) {
        if (clip.id == selectedClipId) {
          assetId = clip.assetId;
        }
      }
    }
    if (assetId == null) {
      return null;
    }
    for (final asset in _assetLibrary.value) {
      if (asset.id == assetId) {
        return asset;
      }
    }
    return null;
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _stopPlayback();
      return;
    }
    _isPlaying = true;
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _fps).round()),
      (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentSeconds += 1 / _fps;
          if (_currentSeconds >= _timelineDuration) {
            _currentSeconds = _timelineDuration;
            _stopPlayback();
          }
        });
      },
    );
    setState(() {});
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _isPlaying = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _setCurrentSeconds(double seconds) {
    setState(() {
      _currentSeconds = seconds.clamp(0.0, _timelineDuration).toDouble();
    });
  }

  void _selectClip(String clipId) {
    setState(() {
      _selectedClipId = clipId;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedClipId = null;
    });
  }

  void _splitSelectedClip() {
    final selectedClipId = _selectedClipId;
    if (selectedClipId == null) {
      return;
    }
    for (var trackIndex = 0; trackIndex < _tracks.length; trackIndex++) {
      var cursor = 0.0;
      final clips = List<TimelineClipData>.from(_tracks[trackIndex].clips);
      for (var clipIndex = 0; clipIndex < clips.length; clipIndex++) {
        final clip = clips[clipIndex];
        final clipStart = cursor;
        final clipEnd = cursor + clip.duration;
        if (clip.id != selectedClipId ||
            clip.type != TimelineClipType.media ||
            _currentSeconds <= clipStart + 0.1 ||
            _currentSeconds >= clipEnd - 0.1) {
          cursor = clipEnd;
          continue;
        }
        final leftDuration = _currentSeconds - clipStart;
        final rightDuration = clipEnd - _currentSeconds;
        final splitGroupId = clip.splitGroupId ?? 'split-${clip.assetId}-${DateTime.now().millisecondsSinceEpoch}';
        final leftClip = clip.copyWith(
          duration: leftDuration,
          id: '${clip.id}-a',
          splitGroupId: splitGroupId,
        );
        final rightClip = clip.copyWith(
          duration: rightDuration,
          id: '${clip.id}-b',
          splitGroupId: splitGroupId,
          sourceOffsetSeconds: (clip.sourceOffsetSeconds ?? 0) + leftDuration,
        );
        clips
          ..removeAt(clipIndex)
          ..insertAll(clipIndex, [leftClip, rightClip]);
        setState(() {
          _tracks = _replaceTrack(trackIndex, clips);
          _selectedClipId = rightClip.id;
        });
        return;
      }
    }
  }

  void _duplicateSelectedClip() {
    final selectedClipId = _selectedClipId;
    if (selectedClipId == null) {
      return;
    }
    for (var trackIndex = 0; trackIndex < _tracks.length; trackIndex++) {
      final clips = List<TimelineClipData>.from(_tracks[trackIndex].clips);
      final clipIndex =
          clips.indexWhere((clip) => clip.id == selectedClipId);
      if (clipIndex < 0) {
        continue;
      }
      final clip = clips[clipIndex];
      final duplicate = clip.copyWith(
        id: '${clip.id}-copy-${DateTime.now().millisecondsSinceEpoch}',
      );
      clips.insert(clipIndex + 1, duplicate);
      setState(() {
        _tracks = _replaceTrack(trackIndex, clips);
        _selectedClipId = duplicate.id;
      });
      return;
    }
  }

  void _deleteSelectedClip() {
    final selectedClipId = _selectedClipId;
    if (selectedClipId == null) {
      return;
    }
    for (var trackIndex = 0; trackIndex < _tracks.length; trackIndex++) {
      final clips = List<TimelineClipData>.from(_tracks[trackIndex].clips);
      final previousLength = clips.length;
      clips.removeWhere((clip) => clip.id == selectedClipId);
      if (clips.length == previousLength) {
        continue;
      }
      setState(() {
        _tracks = _replaceTrack(trackIndex, clips);
        _selectedClipId = clips.isEmpty ? null : clips.last.id;
      });
      return;
    }
  }

  void _trimSelectedClipLeft() {
    _trimSelectedClip(fromStart: true);
  }

  void _trimSelectedClipRight() {
    _trimSelectedClip(fromStart: false);
  }

  void _trimSelectedClip({required bool fromStart}) {
    final selectedClipId = _selectedClipId;
    if (selectedClipId == null) {
      return;
    }
    for (var trackIndex = 0; trackIndex < _tracks.length; trackIndex++) {
      var cursor = 0.0;
      final clips = List<TimelineClipData>.from(_tracks[trackIndex].clips);
      for (var clipIndex = 0; clipIndex < clips.length; clipIndex++) {
        final clip = clips[clipIndex];
        final clipStart = cursor;
        final clipEnd = cursor + clip.duration;
        if (clip.id != selectedClipId || clip.type != TimelineClipType.media) {
          cursor = clipEnd;
          continue;
        }
        if (fromStart) {
          final nextStart = _currentSeconds.clamp(clipStart, clipEnd - 0.25);
          final delta = nextStart - clipStart;
          clips[clipIndex] = clip.copyWith(
            duration: clip.duration - delta,
            sourceOffsetSeconds: (clip.sourceOffsetSeconds ?? 0) + delta,
          );
        } else {
          final nextEnd = _currentSeconds.clamp(clipStart + 0.25, clipEnd);
          clips[clipIndex] = clip.copyWith(duration: nextEnd - clipStart);
        }
        setState(() {
          _tracks = _replaceTrack(trackIndex, clips);
        });
        return;
      }
    }
  }

  void _reorderClip(String clipId, int insertionIndex) {
    for (var trackIndex = 0; trackIndex < _tracks.length; trackIndex++) {
      final clips = List<TimelineClipData>.from(_tracks[trackIndex].clips);
      final clipIndex = clips.indexWhere((clip) => clip.id == clipId);
      if (clipIndex < 0) {
        continue;
      }
      final clip = clips.removeAt(clipIndex);
      final targetIndex = insertionIndex.clamp(0, clips.length);
      clips.insert(targetIndex, clip);
      setState(() {
        _tracks = _replaceTrack(trackIndex, clips);
        _selectedClipId = clip.id;
      });
      return;
    }
  }

  List<TimelineTrackData> _replaceTrack(int index, List<TimelineClipData> clips) {
    final nextTracks = List<TimelineTrackData>.from(_tracks);
    nextTracks[index] = nextTracks[index].copyWith(clips: clips);
    return List<TimelineTrackData>.unmodifiable(nextTracks);
  }

  void _handleDockTab(EditorMediaTab tab) {
    setState(() {
      _activeTab = tab;
    });
    _openMediaSheet(tab);
  }

  Future<void> _openMediaSheet(EditorMediaTab tab) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return MediaBottomSheet(
          activeTab: tab,
          assetsListenable: _assetLibrary,
          onImportTap: (importTab) async {
            final newAsset = _buildImportedMockAsset(importTab);
            _assetLibrary.value = [..._assetLibrary.value, newAsset];
          },
          onAssetAdd: (asset) async {
            Navigator.of(context).pop();
            _addAssetToTimeline(asset);
          },
        );
      },
    );
  }

  void _addAssetToTimeline(MockAssetItem asset) {
    final trackIndex = _trackIndexForTab(asset.tab);
    if (trackIndex < 0) {
      return;
    }
    final clipId = 'clip-${asset.id}-${DateTime.now().millisecondsSinceEpoch}';
    final clip = TimelineClipData(
      id: clipId,
      assetId: asset.id,
      duration: asset.durationSeconds ?? 3.5,
      tone: TimelineClipTone.hero,
      type: TimelineClipType.media,
      sourceOffsetSeconds: 0,
      label: asset.label,
    );
    final clips = List<TimelineClipData>.from(_tracks[trackIndex].clips)
      ..add(clip);
    setState(() {
      _tracks = _replaceTrack(trackIndex, clips);
      _selectedClipId = clip.id;
      _activeTab = asset.tab == EditorMediaTab.image
          ? EditorMediaTab.image
          : asset.tab == EditorMediaTab.video
              ? EditorMediaTab.video
              : _activeTab;
    });
  }

  int _trackIndexForTab(EditorMediaTab tab) {
    final kind = switch (tab) {
      EditorMediaTab.video => TimelineTrackKind.video,
      EditorMediaTab.image => TimelineTrackKind.image,
      EditorMediaTab.audio => TimelineTrackKind.audio,
      EditorMediaTab.text => TimelineTrackKind.text,
      EditorMediaTab.lipSync => TimelineTrackKind.lipSync,
    };
    return _tracks.indexWhere((track) => track.kind == kind);
  }

  MockAssetItem _buildImportedMockAsset(EditorMediaTab tab) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return MockAssetItem(
      id: 'asset-$stamp',
      tab: tab,
      label: switch (tab) {
        EditorMediaTab.video => 'Imported Video $stamp',
        EditorMediaTab.image => 'Imported Image $stamp',
        EditorMediaTab.audio => 'Imported Audio $stamp',
        EditorMediaTab.text => 'Imported Text $stamp',
        EditorMediaTab.lipSync => 'Imported Lip Sync $stamp',
      },
      tone: 80,
      isImported: true,
      durationSeconds: switch (tab) {
        EditorMediaTab.video => 6.0,
        EditorMediaTab.image => 4.0,
        EditorMediaTab.audio => 6.0,
        EditorMediaTab.text => 3.0,
        EditorMediaTab.lipSync => 3.0,
      },
      width: tab == EditorMediaTab.video || tab == EditorMediaTab.image
          ? 1080
          : null,
      height: tab == EditorMediaTab.video || tab == EditorMediaTab.image
          ? 1920
          : null,
    );
  }

  List<MockAssetItem> _buildInitialAssets() {
    return const <MockAssetItem>[
      MockAssetItem(
        id: 'portrait-video',
        tab: EditorMediaTab.video,
        label: 'Portrait Video',
        tone: 80,
        isImported: true,
        durationSeconds: 14,
        width: 1080,
        height: 1920,
      ),
      MockAssetItem(
        id: 'broll-video',
        tab: EditorMediaTab.video,
        label: 'B-Roll',
        tone: 68,
        isImported: true,
        durationSeconds: 6,
        width: 1920,
        height: 1080,
      ),
      MockAssetItem(
        id: 'cover-image',
        tab: EditorMediaTab.image,
        label: 'Cover Image',
        tone: 60,
        isImported: true,
        durationSeconds: 5,
        width: 1080,
        height: 1920,
      ),
      MockAssetItem(
        id: 'voice-audio',
        tab: EditorMediaTab.audio,
        label: 'Voiceover',
        tone: 55,
        isImported: true,
        durationSeconds: 14,
      ),
      MockAssetItem(
        id: 'caption-text',
        tab: EditorMediaTab.text,
        label: 'Subtitle Block',
        tone: 42,
        isImported: true,
        durationSeconds: 4,
      ),
      MockAssetItem(
        id: 'lipsync-track',
        tab: EditorMediaTab.lipSync,
        label: 'Lip Sync',
        tone: 35,
        isImported: true,
        durationSeconds: 4,
      ),
    ];
  }

  List<TimelineTrackData> _buildInitialTracks() {
    return const <TimelineTrackData>[
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: <TimelineClipData>[
          TimelineClipData(
            id: 'clip-video-1',
            duration: 14,
            type: TimelineClipType.media,
            tone: TimelineClipTone.hero,
            assetId: 'portrait-video',
            label: 'Portrait Video',
            sourceOffsetSeconds: 0,
          ),
        ],
      ),
      TimelineTrackData(
        kind: TimelineTrackKind.audio,
        clips: <TimelineClipData>[
          TimelineClipData(
            id: 'clip-audio-1',
            duration: 14,
            type: TimelineClipType.media,
            tone: TimelineClipTone.heroMuted,
            assetId: 'voice-audio',
            label: 'Voiceover',
            sourceOffsetSeconds: 0,
          ),
        ],
      ),
      TimelineTrackData(
        kind: TimelineTrackKind.text,
        clips: <TimelineClipData>[
          TimelineClipData(
            id: 'clip-text-placeholder',
            duration: 3,
            type: TimelineClipType.placeholder,
            tone: TimelineClipTone.placeholder,
            label: 'Add Text',
          ),
        ],
      ),
    ];
  }

  void _handleShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('FusionX Clean UI is UI-only. Export/backend are excluded.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedAsset = _selectedAsset;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Container(
          color: FxPalette.background,
          child: Column(
            children: [
              EditorTopBar(
                onShare: _handleShare,
                isExporting: false,
                exportProgress: 0,
              ),
              Expanded(
                flex: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 220),
                  child: PreviewStage(
                    workspaceAspectRatio: _workspaceAspectRatio,
                    child: _CleanPreviewCanvas(
                      asset: selectedAsset,
                      selectedClipId: _selectedClipId,
                      currentSeconds: _currentSeconds,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                flex: 4,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                  decoration: BoxDecoration(
                    color: FxPalette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FxPalette.divider, width: 1),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
                        child: EditorToolsBar(
                          embedded: true,
                          isPlaying: _isPlaying,
                          onSplit: _selectedClipId == null ? null : _splitSelectedClip,
                          onTrimRight: _selectedClipId == null ? null : _trimSelectedClipRight,
                          onTrimLeft: _selectedClipId == null ? null : _trimSelectedClipLeft,
                          onDuplicate: _selectedClipId == null ? null : _duplicateSelectedClip,
                          onDelete: _selectedClipId == null ? null : _deleteSelectedClip,
                          onPlayToggle: _togglePlayback,
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: FxPalette.dividerSoft.withOpacity(0.9),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                          child: TimelinePanel(
                            embedded: true,
                            tracks: _tracks,
                            currentSeconds: _currentSeconds,
                            timelineDuration: _timelineDuration,
                            isPlaying: _isPlaying,
                            selectedClipId: _selectedClipId,
                            onTimeChanged: _setCurrentSeconds,
                            onClipSelected: _selectClip,
                            onClipReorder: _reorderClip,
                            onBackgroundTap: _clearSelection,
                            assetPathResolver: (_) => null,
                            onScrubStateChanged: (_) {},
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: FxPalette.dividerSoft.withOpacity(0.9),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                        child: MediaDock(
                          activeTab: _activeTab,
                          onAddTap: () => _openMediaSheet(
                            _activeTab == EditorMediaTab.image
                                ? EditorMediaTab.image
                                : EditorMediaTab.video,
                          ),
                          onToolTap: _handleDockTab,
                          embedded: true,
                        ),
                      ),
                    ],
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

class _CleanPreviewCanvas extends StatelessWidget {
  const _CleanPreviewCanvas({
    required this.asset,
    required this.selectedClipId,
    required this.currentSeconds,
  });

  final MockAssetItem? asset;
  final String? selectedClipId;
  final double currentSeconds;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = asset?.aspectRatio ?? (9 / 16);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            FxPalette.previewTop,
            FxPalette.previewBottom,
          ],
        ),
      ),
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  FxPalette.surfaceRaised,
                  Colors.black.withOpacity(0.78),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.06),
                width: 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          FxPalette.accentSoft.withOpacity(0.42),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.05),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'FusionX Clean UI',
                          style: TextStyle(
                            color: FxPalette.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.smart_display_rounded,
                        color: FxPalette.textPrimary,
                        size: 56,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        asset?.label ?? 'Visual Stage',
                        style: const TextStyle(
                          color: FxPalette.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        selectedClipId == null
                            ? 'UI-only canvas with no backend, engine, or player.'
                            : 'Selected clip: $selectedClipId',
                        style: const TextStyle(
                          color: FxPalette.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Time ${currentSeconds.toStringAsFixed(2)}s',
                        style: const TextStyle(
                          color: FxPalette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
