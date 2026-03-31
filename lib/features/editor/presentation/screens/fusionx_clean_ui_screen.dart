import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/media/device_media_library_bridge.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../engine/bridge/method_channel_fusionx_engine_bridge.dart';
import '../../../../engine/contracts/engine_contracts.dart';
import '../../../../engine/models/engine_time.dart';
import '../models/device_media_item.dart';
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
  static const int _defaultProjectWidth = 1080;
  static const int _defaultProjectHeight = 1920;
  static const int _previewSurfaceWidth = 720;
  static const int _previewSurfaceHeight = 1280;
  static const int _minimumTrimUs = 250000;
  static const int _scrubSettleToleranceUs = 40000;
  static const int _defaultFrameDurationUs = 33333;
  static const String _primaryClipId = 'clip-primary';
  static const String _primarySplitGroupId = 'split-primary';
  static const List<EditorMediaTab> _mediaSheetTabs = <EditorMediaTab>[
    EditorMediaTab.video,
    EditorMediaTab.image,
  ];

  late final ValueNotifier<List<MockAssetItem>> _assetLibrary;
  final ValueNotifier<int> _previewTimelineTimeUs = ValueNotifier<int>(0);
  final MethodChannelFusionXEngineBridge _engineBridge =
      MethodChannelFusionXEngineBridge();
  final DeviceMediaLibraryBridge _deviceMediaBridge =
      DeviceMediaLibraryBridge();

  StreamSubscription<FusionXEngineEvent>? _eventsSubscription;

  EditorMediaTab _activeTab = EditorMediaTab.video;
  List<TimelineTrackData> _tracks = const <TimelineTrackData>[];
  String? _selectedClipId;
  String? _selectedAssetId;
  String _playbackStatus = FusionXTransportState.idle.name;
  String? _lastError;
  int? _textureId;
  bool _renderTargetAttached = false;
  bool _engineAvailable = true;
  bool _firstFrameRendered = false;
  bool _isTimelineScrubbing = false;
  bool _isTimelineScrubSettling = false;
  int _projectWidth = _defaultProjectWidth;
  int _projectHeight = _defaultProjectHeight;
  int _sourceDurationUs = 0;
  int _trimStartUs = 0;
  int _trimEndUs = 0;
  int _sourceTimeUs = 0;
  int _timelineTimeUs = 0;
  int _sourceFrameDurationUs = _defaultFrameDurationUs;
  Map<EditorMediaTab, List<DeviceMediaItem>> _deviceMedia =
      <EditorMediaTab, List<DeviceMediaItem>>{
    EditorMediaTab.video: const <DeviceMediaItem>[],
    EditorMediaTab.image: const <DeviceMediaItem>[],
  };
  Map<EditorMediaTab, bool> _deviceMediaLoading = <EditorMediaTab, bool>{
    EditorMediaTab.video: false,
    EditorMediaTab.image: false,
  };
  Map<EditorMediaTab, String?> _deviceMediaErrors = <EditorMediaTab, String?>{
    EditorMediaTab.video: null,
    EditorMediaTab.image: null,
  };
  final Map<String, Future<Uint8List?>> _thumbnailRequests =
      <String, Future<Uint8List?>>{};
  Future<void>? _activeScrubDispatch;
  Future<void>? _timelineScrubCompletionTask;
  int? _pendingScrubTimelineTimeUs;
  int? _activeScrubTimelineTimeUs;
  int? _stableScrubTimelineTimeUs;
  bool _pendingScrubForceReprepare = false;
  bool _scrubImmediateDispatchRequested = false;
  bool _immediateDispatchOnDirectionFlip = false;
  int? _lastQueuedScrubTimelineTimeUs;
  int? _lastRawScrubTimelineTimeUs;
  int _lastScrubDirection = 0;
  bool _nativeScrubReady = false;
  bool _scrubDispatchScheduled = false;
  bool _isTimelineScrubHandoffPending = false;
  int _splitClipSequence = 1;
  List<TimelineClipData> _videoTimelineClips = const <TimelineClipData>[];

  bool get _isAndroidFoundationSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _hasClip => _selectedAsset != null && _sourceDurationUs > 0;

  bool get _isPlaying => _playbackStatus == FusionXTransportState.playing.name;

  double get _workspaceAspectRatio {
    if (_projectHeight <= 0) {
      return 9 / 16;
    }
    return _projectWidth / _projectHeight;
  }

  double get _timelineDuration {
    if (_videoTimelineClips.isNotEmpty) {
      final total = _videoTimelineClips.fold<double>(
        0,
        (sum, clip) => sum + clip.duration,
      );
      if (total > 0) {
        return total;
      }
    }
    return _hasClip
        ? math.max(0.25, (_trimEndUs - _trimStartUs) / 1000000).toDouble()
        : 12;
  }

  MockAssetItem? get _selectedAsset {
    final selectedAssetId = _selectedAssetId;
    if (selectedAssetId == null) {
      return null;
    }
    for (final asset in _assetLibrary.value) {
      if (asset.id == selectedAssetId) {
        return asset;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _assetLibrary = ValueNotifier<List<MockAssetItem>>(const <MockAssetItem>[]);
    _videoTimelineClips = _buildInitialTimelineClips();
    _tracks = _buildPhaseOneTracks();
    _eventsSubscription = _engineBridge.events.listen(_handleEngineEvent);
    unawaited(_initializeFoundation());
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _pendingScrubTimelineTimeUs = null;
    _pendingScrubForceReprepare = false;
    _scrubImmediateDispatchRequested = false;
    _immediateDispatchOnDirectionFlip = false;
    _nativeScrubReady = false;
    if (_renderTargetAttached) {
      unawaited(
        _engineBridge.dispatch(
          const FusionXEngineCommand(
            type: FusionXEngineCommandType.detachRenderTarget,
          ),
        ),
      );
    }
    unawaited(_engineBridge.dispose());
    _previewTimelineTimeUs.dispose();
    _assetLibrary.dispose();
    super.dispose();
  }

  Future<void> _initializeFoundation() async {
    if (!_isAndroidFoundationSupported) {
      setState(() {
        _engineAvailable = false;
      });
      return;
    }

    try {
      await _engineBridge.initialize();
      final result = await _engineBridge.attachRenderTarget(
        width: _previewSurfaceWidth,
        height: _previewSurfaceHeight,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _textureId = result.textureId;
        _renderTargetAttached = result.textureId >= 0;
      });
      unawaited(_warmDeviceMediaLibraryIfPermitted());
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() {
        _engineAvailable = false;
        _lastError = 'Native playback bridge is unavailable in this build.';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _engineAvailable = false;
        _lastError = error.message ?? 'Unable to attach the native preview.';
      });
    }
  }

  void _handleEngineEvent(FusionXEngineEvent event) {
    if (!mounted) {
      return;
    }

    switch (event.type) {
      case FusionXEngineEventType.ready:
        setState(() {
          final textureId =
              (event.payload['textureId'] as num?)?.toInt() ?? _textureId;
          _textureId = textureId;
          if (_playbackStatus == FusionXTransportState.idle.name) {
            _playbackStatus = FusionXTransportState.ready.name;
          }
        });
      case FusionXEngineEventType.previewTargetChanged:
        setState(() {
          _textureId = (event.payload['textureId'] as num?)?.toInt() ?? _textureId;
        });
      case FusionXEngineEventType.durationResolved:
        final sourceDurationUs =
            (event.payload['sourceDurationUs'] as num?)?.toInt() ?? 0;
        final trimStartUs =
            (event.payload['trimStartUs'] as num?)?.toInt() ?? 0;
        final trimEndUs =
            (event.payload['trimEndUs'] as num?)?.toInt() ?? sourceDurationUs;
        final sourceWidth =
            (event.payload['sourceWidth'] as num?)?.toInt() ?? _projectWidth;
        final sourceHeight =
            (event.payload['sourceHeight'] as num?)?.toInt() ?? _projectHeight;
        final sourceFrameDurationUs =
            (event.payload['sourceFrameDurationUs'] as num?)?.toInt() ??
                _sourceFrameDurationUs;
        _updateSelectedAssetMetadata(
          sourceDurationUs: sourceDurationUs,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
        setState(() {
          _sourceDurationUs = sourceDurationUs;
          _trimStartUs = trimStartUs;
          _trimEndUs = trimEndUs;
          _projectWidth = sourceWidth > 0 ? sourceWidth : _defaultProjectWidth;
          _projectHeight =
              sourceHeight > 0 ? sourceHeight : _defaultProjectHeight;
          _sourceFrameDurationUs = sourceFrameDurationUs > 0
              ? sourceFrameDurationUs
              : _defaultFrameDurationUs;
          _activeScrubTimelineTimeUs = null;
          _stableScrubTimelineTimeUs = null;
          _pendingScrubForceReprepare = false;
          _scrubImmediateDispatchRequested = false;
          _immediateDispatchOnDirectionFlip = false;
          _lastQueuedScrubTimelineTimeUs = null;
          _lastRawScrubTimelineTimeUs = null;
          _lastScrubDirection = 0;
          _videoTimelineClips = _buildInitialTimelineClips();
          _tracks = _buildPhaseOneTracks();
          _selectedClipId =
              _videoTimelineClips.isNotEmpty ? _videoTimelineClips.first.id : null;
        });
        _previewTimelineTimeUs.value = 0;
      case FusionXEngineEventType.positionChanged:
        final sourceTimeUs =
            (event.payload['sourceTimeUs'] as num?)?.toInt() ?? _sourceTimeUs;
        final timelineTimeUs =
            (event.payload['timelineTimeUs'] as num?)?.toInt() ?? 0;
        final canAcceptTimelineUpdate = !_isTimelineScrubbing &&
            !_isTimelineScrubHandoffPending &&
            (!_isTimelineScrubSettling ||
                (timelineTimeUs - _timelineTimeUs).abs() <=
                    _scrubSettleToleranceUs);
        setState(() {
          _sourceTimeUs = sourceTimeUs;
          if (canAcceptTimelineUpdate) {
            _timelineTimeUs = timelineTimeUs;
          }
          if (_isTimelineScrubSettling && canAcceptTimelineUpdate) {
            _isTimelineScrubSettling = false;
          }
        });
        if (canAcceptTimelineUpdate) {
          _previewTimelineTimeUs.value = timelineTimeUs;
        }
      case FusionXEngineEventType.playbackStateChanged:
        final state = event.payload['state'] as String? ?? _playbackStatus;
        setState(() {
          _playbackStatus = state;
        });
      case FusionXEngineEventType.firstFrameRendered:
        setState(() {
          _firstFrameRendered = true;
        });
      case FusionXEngineEventType.scrubFrameAvailable:
        return;
      case FusionXEngineEventType.trimChanged:
        final trimStartUs =
            (event.payload['trimStartUs'] as num?)?.toInt() ?? _trimStartUs;
        final trimEndUs =
            (event.payload['trimEndUs'] as num?)?.toInt() ?? _trimEndUs;
        setState(() {
          _trimStartUs = trimStartUs;
          _trimEndUs = trimEndUs;
          _sourceTimeUs = trimStartUs;
          _timelineTimeUs = 0;
          _activeScrubTimelineTimeUs = null;
          _stableScrubTimelineTimeUs = null;
          _pendingScrubForceReprepare = false;
          _scrubImmediateDispatchRequested = false;
          _immediateDispatchOnDirectionFlip = false;
          _lastQueuedScrubTimelineTimeUs = null;
          _lastRawScrubTimelineTimeUs = null;
          _lastScrubDirection = 0;
          _videoTimelineClips = _buildInitialTimelineClips();
          _tracks = _buildPhaseOneTracks();
          _selectedClipId =
              _videoTimelineClips.isNotEmpty ? _videoTimelineClips.first.id : null;
        });
        _previewTimelineTimeUs.value = 0;
      case FusionXEngineEventType.error:
        setState(() {
          _playbackStatus = FusionXTransportState.error.name;
          _lastError = event.payload['message'] as String? ?? 'Unknown error';
        });
    }
  }

  void _updateSelectedAssetMetadata({
    required int sourceDurationUs,
    required int sourceWidth,
    required int sourceHeight,
  }) {
    final selectedAsset = _selectedAsset;
    if (selectedAsset == null) {
      return;
    }
    _upsertAsset(
      selectedAsset.copyWith(
        durationSeconds: sourceDurationUs / 1000000,
        width: sourceWidth > 0 ? sourceWidth : selectedAsset.width,
        height: sourceHeight > 0 ? sourceHeight : selectedAsset.height,
      ),
    );
  }

  List<TimelineClipData> _buildInitialTimelineClips() {
    final selectedAsset = _selectedAsset;
    final clipDurationSeconds = (_trimEndUs - _trimStartUs) / 1000000;
    if (selectedAsset == null || clipDurationSeconds <= 0) {
      return const <TimelineClipData>[];
    }

    return <TimelineClipData>[
      TimelineClipData(
        id: _primaryClipId,
        duration: math.max(0.25, clipDurationSeconds).toDouble(),
        type: TimelineClipType.media,
        tone: TimelineClipTone.hero,
        assetId: selectedAsset.id,
        label: selectedAsset.label,
        sourceOffsetSeconds: _trimStartUs / 1000000,
        filmstripReferenceOffsetSeconds: _trimStartUs / 1000000,
        filmstripReferenceDurationSeconds:
            math.max(0.25, clipDurationSeconds).toDouble(),
      ),
    ];
  }

  List<TimelineTrackData> _buildPhaseOneTracks() {
    return <TimelineTrackData>[
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: List<TimelineClipData>.unmodifiable(_videoTimelineClips),
      ),
    ];
  }

  void _upsertAsset(MockAssetItem asset) {
    final nextAssets = List<MockAssetItem>.from(_assetLibrary.value);
    final existingIndex =
        nextAssets.indexWhere((candidate) => candidate.id == asset.id);
    if (existingIndex >= 0) {
      nextAssets[existingIndex] = asset;
    } else {
      nextAssets.insert(0, asset);
    }
    _assetLibrary.value = List<MockAssetItem>.unmodifiable(nextAssets);
  }

  MockAssetItem? _findAssetByPath(String path) {
    for (final asset in _assetLibrary.value) {
      if (asset.localPath == path) {
        return asset;
      }
    }
    return null;
  }

  void _handleDockTab(EditorMediaTab tab) {
    setState(() {
      _activeTab = tab;
    });
    _showPhaseLaterMessage(tab);
  }

  Future<void> _openMediaSheet(EditorMediaTab initialTab) async {
    var sheetTab = _mediaSheetTabs.contains(initialTab)
        ? initialTab
        : EditorMediaTab.video;
    String? selectedMediaId;
    unawaited(_ensureDeviceMediaLoaded(sheetTab));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final mediaItems = _deviceMediaForTab(sheetTab);
            final isLoading = _isDeviceMediaLoading(sheetTab);
            final errorMessage = _deviceMediaErrorForTab(sheetTab);
            final importEnabled =
                sheetTab == EditorMediaTab.video && selectedMediaId != null;
            final importHint = sheetTab == EditorMediaTab.video
                ? selectedMediaId == null
                    ? 'Select one video, then press Import.'
                    : null
                : 'Image import will be wired after the native image preview path is added.';

            return MediaBottomSheet(
              activeTab: sheetTab,
              mediaItems: mediaItems,
              selectedMediaId: selectedMediaId,
              isLoading: isLoading,
              errorMessage: errorMessage,
              importEnabled: importEnabled,
              importHint: importHint,
              thumbnailLoader: _loadDeviceMediaThumbnail,
              onTabChanged: (tab) {
                setSheetState(() {
                  sheetTab = tab;
                  selectedMediaId = null;
                });
                unawaited(_ensureDeviceMediaLoaded(tab));
              },
              onMediaSelected: (item) {
                setSheetState(() {
                  selectedMediaId = item.id;
                });
              },
              onImport: () async {
                DeviceMediaItem? selectedItem;
                for (final item in mediaItems) {
                  if (item.id == selectedMediaId) {
                    selectedItem = item;
                    break;
                  }
                }
                if (selectedItem == null) {
                  return;
                }
                if (selectedItem.tab != EditorMediaTab.video) {
                  _showPhaseLaterMessage(selectedItem.tab);
                  return;
                }
                Navigator.of(context).pop();
                await Future<void>.delayed(const Duration(milliseconds: 120));
                await _importDeviceMedia(selectedItem);
              },
            );
          },
        );
      },
    );
  }

  List<DeviceMediaItem> _deviceMediaForTab(EditorMediaTab tab) {
    return _deviceMedia[tab] ?? const <DeviceMediaItem>[];
  }

  bool _isDeviceMediaLoading(EditorMediaTab tab) {
    return _deviceMediaLoading[tab] ?? false;
  }

  String? _deviceMediaErrorForTab(EditorMediaTab tab) {
    return _deviceMediaErrors[tab];
  }

  Future<void> _warmDeviceMediaLibraryIfPermitted() async {
    if (!_isAndroidFoundationSupported) {
      return;
    }

    try {
      final videoGranted = await _deviceMediaBridge.hasMediaPermission(
        EditorMediaTab.video,
      );
      if (!mounted || !videoGranted) {
        return;
      }
      await _ensureDeviceMediaLoaded(EditorMediaTab.video);

      final imageGranted = await _deviceMediaBridge.hasMediaPermission(
        EditorMediaTab.image,
      );
      if (!mounted || !imageGranted) {
        return;
      }
      await _ensureDeviceMediaLoaded(EditorMediaTab.image);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _ensureDeviceMediaLoaded(
    EditorMediaTab tab, {
    bool force = false,
  }) async {
    if (!_mediaSheetTabs.contains(tab)) {
      return;
    }
    if ((_deviceMediaLoading[tab] ?? false) && !force) {
      return;
    }
    if (!force && (_deviceMedia[tab]?.isNotEmpty ?? false)) {
      return;
    }

    setState(() {
      _deviceMediaLoading = <EditorMediaTab, bool>{
        ..._deviceMediaLoading,
        tab: true,
      };
      _deviceMediaErrors = <EditorMediaTab, String?>{
        ..._deviceMediaErrors,
        tab: null,
      };
    });

    try {
      final mediaItems = await _deviceMediaBridge.listMedia(tab);
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceMedia = <EditorMediaTab, List<DeviceMediaItem>>{
          ..._deviceMedia,
          tab: mediaItems,
        };
        _deviceMediaLoading = <EditorMediaTab, bool>{
          ..._deviceMediaLoading,
          tab: false,
        };
      });
      _primeDeviceMediaThumbnails(tab);
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceMediaLoading = <EditorMediaTab, bool>{
          ..._deviceMediaLoading,
          tab: false,
        };
        _deviceMediaErrors = <EditorMediaTab, String?>{
          ..._deviceMediaErrors,
          tab: error.message ?? 'Unable to access the Android media library.',
        };
      });
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceMediaLoading = <EditorMediaTab, bool>{
          ..._deviceMediaLoading,
          tab: false,
        };
        _deviceMediaErrors = <EditorMediaTab, String?>{
          ..._deviceMediaErrors,
          tab: 'The Android media browser bridge is unavailable in this build.',
        };
      });
    }
  }

  void _primeDeviceMediaThumbnails(EditorMediaTab tab) {
    final mediaItems = _deviceMediaForTab(tab);
    for (final item in mediaItems.take(9)) {
      unawaited(_loadDeviceMediaThumbnail(item));
    }
  }

  Future<Uint8List?> _loadDeviceMediaThumbnail(DeviceMediaItem item) {
    return _thumbnailRequests.putIfAbsent(
      item.id,
      () => _deviceMediaBridge.loadThumbnail(item: item),
    );
  }

  Future<void> _importDeviceMedia(DeviceMediaItem item) async {
    if (!_canUseNativePlayback) {
      _showFoundationUnavailableMessage();
      return;
    }
    final existingAsset = _findAssetByPath(item.uri);
    final posterBytes = await _loadDeviceMediaThumbnail(item);
    final baseAsset = existingAsset ?? _buildImportedVideoAsset(item);
    final asset = baseAsset.copyWith(
      posterBytes: posterBytes,
      width: item.width ?? baseAsset.width,
      height: item.height ?? baseAsset.height,
      durationSeconds: item.durationUs == null
          ? baseAsset.durationSeconds
          : item.durationUs! / 1000000,
    );
    _upsertAsset(asset);
    await _loadAsset(asset);
  }

  MockAssetItem _buildImportedVideoAsset(DeviceMediaItem item) {
    final clipCount = _assetLibrary.value
        .where((asset) => asset.tab == EditorMediaTab.video)
        .length;
    return MockAssetItem(
      id: 'video-${DateTime.now().millisecondsSinceEpoch}',
      tab: EditorMediaTab.video,
      label:
          item.label.isEmpty ? 'Imported Video ${clipCount + 1}' : item.label,
      tone: 80,
      localPath: item.uri,
      isImported: true,
      durationSeconds:
          item.durationUs == null ? null : item.durationUs! / 1000000,
      width: item.width,
      height: item.height,
    );
  }

  Future<void> _loadAsset(MockAssetItem asset) async {
    if (asset.tab != EditorMediaTab.video) {
      _showPhaseLaterMessage(asset.tab);
      return;
    }
    if (!_canUseNativePlayback || asset.localPath == null) {
      _showFoundationUnavailableMessage();
      return;
    }

    final knownDurationUs = ((asset.durationSeconds ?? 0) * 1000000).round();
    setState(() {
      _activeTab = asset.tab;
      _selectedAssetId = asset.id;
      _selectedClipId = _primaryClipId;
      _playbackStatus = 'loading';
      _lastError = null;
      _firstFrameRendered = false;
      _sourceDurationUs = knownDurationUs;
      _trimStartUs = 0;
      _trimEndUs = knownDurationUs;
      _sourceTimeUs = 0;
      _timelineTimeUs = 0;
      _nativeScrubReady = false;
      if (asset.width != null && asset.height != null && asset.height! > 0) {
        _projectWidth = asset.width!;
        _projectHeight = asset.height!;
      } else {
        _projectWidth = _defaultProjectWidth;
        _projectHeight = _defaultProjectHeight;
      }
      _videoTimelineClips = _buildInitialTimelineClips();
      _tracks = _buildPhaseOneTracks();
    });
    _previewTimelineTimeUs.value = 0;

    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: FusionXEngineCommandType.loadClip,
        payload: LoadClipPayload(path: asset.localPath!).toMap(),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (!_hasClip || !_canUseNativePlayback) {
      return;
    }
    if (_isTimelineScrubSettling) {
      await _completeTimelineScrub();
    }
    await _flushPendingScrubDispatches();
    setState(() {});
    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: _isPlaying
            ? FusionXEngineCommandType.pause
            : FusionXEngineCommandType.play,
      ),
    );
  }

  Future<void> _beginNativeScrub() async {
    if (!_hasClip || !_canUseNativePlayback) {
      return;
    }
    if (_nativeScrubReady) {
      return;
    }
    if (_isPlaying) {
      await _engineBridge.dispatch(const FusionXEngineCommand(
        type: FusionXEngineCommandType.pause,
      ));
    }
    await _engineBridge.dispatch(const FusionXEngineCommand(
      type: FusionXEngineCommandType.beginScrub,
    ));
    _nativeScrubReady = true;
    _scheduleScrubDispatch();
  }

  Future<void> _endNativeScrub() async {
    if (!_hasClip || !_canUseNativePlayback) {
      return;
    }
    _queueScrubDispatch(_timelineTimeUs);
    await _flushPendingScrubDispatches();
    _pendingScrubTimelineTimeUs = null;
    _pendingScrubForceReprepare = false;
    _scrubImmediateDispatchRequested = false;
    _immediateDispatchOnDirectionFlip = false;
    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: FusionXEngineCommandType.endScrub,
        payload: EndScrubPayload(
          timelineTime: EngineTime.fromMicroseconds(_timelineTimeUs),
        ).toMap(),
      ),
    );
    _nativeScrubReady = false;
  }

  Future<void> _completeTimelineScrub() async {
    final activeTask = _timelineScrubCompletionTask;
    if (activeTask != null) {
      await activeTask;
      return;
    }
    final task = _completeTimelineScrubInternal();
    _timelineScrubCompletionTask = task;
    try {
      await task;
    } finally {
      if (identical(_timelineScrubCompletionTask, task)) {
        _timelineScrubCompletionTask = null;
      }
    }
  }

  Future<void> _completeTimelineScrubInternal() async {
    if (mounted) {
      setState(() {
        _isTimelineScrubHandoffPending = true;
      });
    }
    try {
      await _endNativeScrub();
    } finally {
      if (mounted) {
        setState(() {
          _isTimelineScrubHandoffPending = false;
          _isTimelineScrubSettling = false;
        });
        _previewTimelineTimeUs.value = _timelineTimeUs;
      }
    }
  }

  void _queueScrubDispatch(
    int timelineTimeUs, {
    bool forceReprepare = false,
    bool immediate = false,
  }) {
    final clampedTimelineTimeUs =
        timelineTimeUs.clamp(0, _trimmedTimelineDurationUs);
    if (!forceReprepare &&
        _lastQueuedScrubTimelineTimeUs == clampedTimelineTimeUs &&
        _pendingScrubTimelineTimeUs == null &&
        _activeScrubTimelineTimeUs == null) {
      return;
    }
    if (!forceReprepare &&
        (_pendingScrubTimelineTimeUs == clampedTimelineTimeUs ||
            _activeScrubTimelineTimeUs == clampedTimelineTimeUs)) {
      return;
    }
    if (forceReprepare) {
      _activeScrubTimelineTimeUs = null;
    }
    if (_pendingScrubTimelineTimeUs != clampedTimelineTimeUs) {
      _pendingScrubForceReprepare = false;
    }
    _pendingScrubForceReprepare =
        _pendingScrubForceReprepare || forceReprepare;
    _scrubImmediateDispatchRequested =
        _scrubImmediateDispatchRequested || immediate;
    _lastQueuedScrubTimelineTimeUs = clampedTimelineTimeUs;
    _pendingScrubTimelineTimeUs = clampedTimelineTimeUs;
    if (!_nativeScrubReady) {
      return;
    }
    _scheduleScrubDispatch(immediate: immediate);
  }

  Future<void> _flushPendingScrubDispatches() async {
    while (_scrubDispatchScheduled || _activeScrubDispatch != null) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _scheduleScrubDispatch({bool immediate = false}) {
    if (!_nativeScrubReady || _scrubDispatchScheduled) {
      return;
    }
    _scrubDispatchScheduled = true;
    void runDispatch() {
      _scrubDispatchScheduled = false;
      if (!mounted || !_nativeScrubReady) {
        return;
      }
      final nextTimelineTimeUs = _pendingScrubTimelineTimeUs;
      if (nextTimelineTimeUs == null) {
        return;
      }
      _pendingScrubTimelineTimeUs = null;
      final forceReprepare = _pendingScrubForceReprepare;
      _pendingScrubForceReprepare = false;
      _scrubImmediateDispatchRequested = false;
      _activeScrubTimelineTimeUs = nextTimelineTimeUs;
      final task = _dispatchScrubTo(
        nextTimelineTimeUs,
        forceReprepare: forceReprepare,
      );
      _activeScrubDispatch = task;
      unawaited(task.whenComplete(() {
        if (identical(_activeScrubDispatch, task)) {
          _activeScrubDispatch = null;
        }
        if (_activeScrubTimelineTimeUs == nextTimelineTimeUs) {
          _activeScrubTimelineTimeUs = null;
        }
        if (mounted && _pendingScrubTimelineTimeUs != null) {
          _scheduleScrubDispatch(immediate: _scrubImmediateDispatchRequested);
        }
      }));
    }

    if (immediate || _scrubImmediateDispatchRequested) {
      scheduleMicrotask(runDispatch);
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback((_) => runDispatch());
  }

  Future<void> _dispatchScrubTo(
    int timelineTimeUs, {
    required bool forceReprepare,
  }) async {
    try {
      await _engineBridge.dispatch(
        FusionXEngineCommand(
          type: FusionXEngineCommandType.scrubTo,
          payload: ScrubToPayload(
            timelineTime: EngineTime.fromMicroseconds(timelineTimeUs),
            forceReprepare: forceReprepare,
          ).toMap(),
        ),
      );
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() {
        _engineAvailable = false;
        _playbackStatus = FusionXTransportState.error.name;
        _lastError = 'Native playback bridge is unavailable in this build.';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _playbackStatus = FusionXTransportState.error.name;
        _lastError = error.message ?? 'Unable to scrub the current clip.';
      });
    }
  }

  void _setCurrentSeconds(double seconds) {
    final clampedSeconds = seconds.clamp(0.0, _timelineDuration).toDouble();
    final rawTimelineTimeUs = (clampedSeconds * 1000000).round();
    final timelineTimeUs = _isTimelineScrubbing
        ? _resolveStableScrubTimelineTimeUs(rawTimelineTimeUs)
        : _snapTimelineTimeUs(rawTimelineTimeUs);
    _timelineTimeUs = timelineTimeUs;
    _previewTimelineTimeUs.value = timelineTimeUs;
    if (!_hasClip || !_canUseNativePlayback) {
      return;
    }
    if (_isTimelineScrubbing) {
      final immediateDispatch = _immediateDispatchOnDirectionFlip;
      _immediateDispatchOnDirectionFlip = false;
      _queueScrubDispatch(
        timelineTimeUs,
        immediate: immediateDispatch,
      );
      return;
    }
    setState(() {});
    unawaited(
      _engineBridge.dispatch(
        FusionXEngineCommand(
          type: FusionXEngineCommandType.seekTo,
          payload: SeekToPayload(
            timelineTime: EngineTime.fromMicroseconds(timelineTimeUs),
          ).toMap(),
        ),
      ),
    );
  }

  int _snapTimelineTimeUs(int timelineTimeUs) {
    final frameDurationUs = _sourceFrameDurationUs > 0
        ? _sourceFrameDurationUs
        : _defaultFrameDurationUs;
    if (frameDurationUs <= 1) {
      return timelineTimeUs.clamp(0, _trimmedTimelineDurationUs);
    }
    final snapped =
        ((timelineTimeUs / frameDurationUs).round()) * frameDurationUs;
    return snapped.clamp(0, _trimmedTimelineDurationUs);
  }

  int _snapTimelineTimeUsTowardDirection(
    int timelineTimeUs,
    int direction,
  ) {
    final frameDurationUs = _sourceFrameDurationUs > 0
        ? _sourceFrameDurationUs
        : _defaultFrameDurationUs;
    if (frameDurationUs <= 1 || direction >= 0) {
      return _snapTimelineTimeUs(timelineTimeUs);
    }
    final clampedTimelineTimeUs =
        timelineTimeUs.clamp(0, _trimmedTimelineDurationUs);
    final snapped = (clampedTimelineTimeUs ~/ frameDurationUs) * frameDurationUs;
    return snapped.clamp(0, _trimmedTimelineDurationUs);
  }

  int _stepStableTimelineTimeUs(
    int timelineTimeUs,
    int direction,
  ) {
    final frameDurationUs = _sourceFrameDurationUs > 0
        ? _sourceFrameDurationUs
        : _defaultFrameDurationUs;
    if (frameDurationUs <= 1 || direction == 0) {
      return timelineTimeUs.clamp(0, _trimmedTimelineDurationUs);
    }
    final steppedTimelineTimeUs = direction < 0
        ? timelineTimeUs - frameDurationUs
        : timelineTimeUs + frameDurationUs;
    return steppedTimelineTimeUs.clamp(0, _trimmedTimelineDurationUs);
  }

  int _resolveStableScrubTimelineTimeUs(int rawTimelineTimeUs) {
    final clampedRawTimelineTimeUs =
        rawTimelineTimeUs.clamp(0, _trimmedTimelineDurationUs);
    final frameDurationUs = _sourceFrameDurationUs > 0
        ? _sourceFrameDurationUs
        : _defaultFrameDurationUs;
    if (frameDurationUs <= 1) {
      _stableScrubTimelineTimeUs = clampedRawTimelineTimeUs;
      return clampedRawTimelineTimeUs;
    }

    final lastRawScrubTimelineTimeUs = _lastRawScrubTimelineTimeUs;
    final rawDirection = lastRawScrubTimelineTimeUs == null
        ? 0
        : clampedRawTimelineTimeUs.compareTo(lastRawScrubTimelineTimeUs);
    final didFlipDirection = rawDirection != 0 &&
        _lastScrubDirection != 0 &&
        rawDirection != _lastScrubDirection;

    var currentStableTimelineTimeUs =
        _stableScrubTimelineTimeUs ?? _snapTimelineTimeUs(clampedRawTimelineTimeUs);
    if (didFlipDirection) {
      currentStableTimelineTimeUs = rawDirection < 0
          ? _stepStableTimelineTimeUs(currentStableTimelineTimeUs, rawDirection)
          : _snapTimelineTimeUsTowardDirection(
              clampedRawTimelineTimeUs,
              rawDirection,
            );
      _stableScrubTimelineTimeUs = currentStableTimelineTimeUs;
      _immediateDispatchOnDirectionFlip = true;
    }

    final hysteresisUs = didFlipDirection ? 0 : math.max(2000, frameDurationUs ~/ 6);
    var forwardThresholdUs =
        currentStableTimelineTimeUs + (frameDurationUs ~/ 2);
    var backwardThresholdUs =
        currentStableTimelineTimeUs - (frameDurationUs ~/ 2);

    if (!didFlipDirection && clampedRawTimelineTimeUs > currentStableTimelineTimeUs) {
      backwardThresholdUs -= hysteresisUs;
    } else if (!didFlipDirection &&
        clampedRawTimelineTimeUs < currentStableTimelineTimeUs) {
      forwardThresholdUs += hysteresisUs;
    }

    var nextStableTimelineTimeUs = currentStableTimelineTimeUs;
    if (clampedRawTimelineTimeUs >= forwardThresholdUs) {
      final framesToAdvance =
          1 + ((clampedRawTimelineTimeUs - forwardThresholdUs) ~/ frameDurationUs);
      nextStableTimelineTimeUs =
          currentStableTimelineTimeUs + (framesToAdvance * frameDurationUs);
    } else if (clampedRawTimelineTimeUs <= backwardThresholdUs) {
      final framesToRewind =
          1 + ((backwardThresholdUs - clampedRawTimelineTimeUs) ~/ frameDurationUs);
      nextStableTimelineTimeUs =
          currentStableTimelineTimeUs - (framesToRewind * frameDurationUs);
    }

    final clampedStableTimelineTimeUs =
        nextStableTimelineTimeUs.clamp(0, _trimmedTimelineDurationUs);
    _lastRawScrubTimelineTimeUs = clampedRawTimelineTimeUs;
    _lastScrubDirection = rawDirection;
    _stableScrubTimelineTimeUs = clampedStableTimelineTimeUs;
    return clampedStableTimelineTimeUs;
  }

  int get _trimmedTimelineDurationUs =>
      (_trimEndUs - _trimStartUs).clamp(0, _sourceDurationUs);

  void _handleTimelineScrubStateChanged(bool isScrubbing) {
    if (_isTimelineScrubbing == isScrubbing) {
      return;
    }
    setState(() {
      _isTimelineScrubbing = isScrubbing;
      if (isScrubbing) {
        _isTimelineScrubHandoffPending = false;
        _isTimelineScrubSettling = false;
        _stableScrubTimelineTimeUs = _snapTimelineTimeUs(_timelineTimeUs);
        _activeScrubTimelineTimeUs = null;
        _pendingScrubForceReprepare = false;
        _scrubImmediateDispatchRequested = false;
        _immediateDispatchOnDirectionFlip = false;
        _lastQueuedScrubTimelineTimeUs = null;
        _lastRawScrubTimelineTimeUs = _timelineTimeUs;
        _lastScrubDirection = 0;
        _timelineTimeUs = _stableScrubTimelineTimeUs!;
      } else if (_hasClip && _canUseNativePlayback) {
        _isTimelineScrubSettling = true;
        _isTimelineScrubHandoffPending = true;
        _activeScrubTimelineTimeUs = null;
        _stableScrubTimelineTimeUs = null;
        _pendingScrubForceReprepare = false;
        _scrubImmediateDispatchRequested = false;
        _immediateDispatchOnDirectionFlip = false;
        _lastQueuedScrubTimelineTimeUs = null;
        _lastRawScrubTimelineTimeUs = null;
        _lastScrubDirection = 0;
      } else {
        _activeScrubTimelineTimeUs = null;
        _stableScrubTimelineTimeUs = null;
        _pendingScrubForceReprepare = false;
        _scrubImmediateDispatchRequested = false;
        _immediateDispatchOnDirectionFlip = false;
        _lastQueuedScrubTimelineTimeUs = null;
        _lastRawScrubTimelineTimeUs = null;
        _lastScrubDirection = 0;
      }
    });
    if (isScrubbing) {
      _previewTimelineTimeUs.value = _timelineTimeUs;
    }
    if (!isScrubbing) {
      _previewTimelineTimeUs.value = _timelineTimeUs;
      if (_hasClip && _canUseNativePlayback) {
        unawaited(_completeTimelineScrub());
      }
    }
    if (isScrubbing) {
      unawaited(_beginNativeScrub());
      return;
    }
  }

  void _selectClip(String clipId) {
    final exists = _videoTimelineClips.any((clip) => clip.id == clipId);
    if (!exists) {
      return;
    }
    setState(() {
      _selectedClipId = clipId;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedClipId = null;
    });
  }

  void _trimSelectedClipLeft() {
    unawaited(_trimSelectedClip(fromStart: true));
  }

  void _trimSelectedClipRight() {
    unawaited(_trimSelectedClip(fromStart: false));
  }

  Future<void> _trimSelectedClip({required bool fromStart}) async {
    if (!_hasClip ||
        !_canUseNativePlayback ||
        _videoTimelineClips.length != 1 ||
        _selectedClipId != _primaryClipId) {
      return;
    }

    final currentSourceUs =
        _sourceTimeUs.clamp(_trimStartUs, _trimEndUs).toInt();
    final nextTrimStartUs = fromStart
        ? currentSourceUs.clamp(0, _trimEndUs - _minimumTrimUs).toInt()
        : _trimStartUs;
    final nextTrimEndUs = fromStart
        ? _trimEndUs
        : currentSourceUs
            .clamp(
              _trimStartUs + _minimumTrimUs,
              _sourceDurationUs,
            )
            .toInt();

    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: FusionXEngineCommandType.setTrim,
        payload: SetTrimPayload(
          trimStartUs: nextTrimStartUs,
          trimEndUs: nextTrimEndUs,
        ).toMap(),
      ),
    );
  }

  void _handleShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Export remains out of scope until preview transport is stable.'),
      ),
    );
  }

  void _showPhaseLaterMessage(EditorMediaTab tab) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tab.label} will be wired in a later engine phase.'),
      ),
    );
  }

  void _showFoundationUnavailableMessage() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isAndroidFoundationSupported
              ? 'Native playback foundation is not ready in this build.'
              : 'This phase currently runs on Android only.',
        ),
      ),
    );
  }

  bool get _canUseNativePlayback =>
      _isAndroidFoundationSupported &&
      _engineAvailable &&
      _renderTargetAttached;

  String? _resolveAssetPath(String assetId) {
    for (final asset in _assetLibrary.value) {
      if (asset.id == assetId) {
        return asset.localPath;
      }
    }
    return null;
  }

  Uint8List? _resolveAssetThumbnail(String assetId) {
    for (final asset in _assetLibrary.value) {
      if (asset.id == assetId) {
        return asset.posterBytes;
      }
    }
    return null;
  }

  bool get _canSplitAtCurrentTime => _resolveSplitCandidate() != null;

  _TimelineClipLocation? _resolveSplitCandidate() {
    if (_videoTimelineClips.isEmpty) {
      return null;
    }
    final minimumSegmentUs = math.max(1, _sourceFrameDurationUs);
    var timelineCursorUs = 0;
    _TimelineClipLocation? fallback;
    final preferredClipId = _selectedClipId;
    for (var index = 0; index < _videoTimelineClips.length; index++) {
      final clip = _videoTimelineClips[index];
      final clipDurationUs = (clip.duration * 1000000).round();
      final clipStartUs = timelineCursorUs;
      final clipEndUs = clipStartUs + clipDurationUs;
      final isInsideClip = _timelineTimeUs > clipStartUs && _timelineTimeUs < clipEndUs;
      if (!isInsideClip) {
        timelineCursorUs = clipEndUs;
        continue;
      }
      final relativeCutUs = _timelineTimeUs - clipStartUs;
      final isValidSplit = relativeCutUs >= minimumSegmentUs &&
          (clipDurationUs - relativeCutUs) >= minimumSegmentUs;
      if (!isValidSplit) {
        timelineCursorUs = clipEndUs;
        continue;
      }
      final location = _TimelineClipLocation(
        clip: clip,
        index: index,
        timelineStartUs: clipStartUs,
        durationUs: clipDurationUs,
        relativeCutUs: relativeCutUs,
      );
      if (preferredClipId != null && clip.id == preferredClipId) {
        return location;
      }
      fallback ??= location;
      timelineCursorUs = clipEndUs;
    }
    return fallback;
  }

  String _nextSplitClipId() => 'clip-split-${_splitClipSequence++}';

  Future<void> _splitSelectedClip() async {
    if (!_canSplitAtCurrentTime) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Move the playhead inside a clip before using Cut.',
          ),
        ),
      );
      return;
    }
    if (_isTimelineScrubSettling) {
      await _completeTimelineScrub();
    }
    final location = _resolveSplitCandidate();
    if (location == null) {
      return;
    }

    final clip = location.clip;
    final leftDurationUs = location.relativeCutUs;
    final rightDurationUs = location.durationUs - location.relativeCutUs;
    final splitGroupId = clip.splitGroupId ?? _primarySplitGroupId;
    final referenceOffsetSeconds =
        clip.filmstripReferenceOffsetSeconds ?? (clip.sourceOffsetSeconds ?? 0);
    final referenceDurationSeconds =
        clip.filmstripReferenceDurationSeconds ?? clip.duration;
    final leftClip = clip.copyWith(
      id: clip.id,
      duration: leftDurationUs / 1000000,
      splitGroupId: splitGroupId,
      filmstripReferenceOffsetSeconds: referenceOffsetSeconds,
      filmstripReferenceDurationSeconds: referenceDurationSeconds,
    );
    final rightClip = clip.copyWith(
      id: _nextSplitClipId(),
      duration: rightDurationUs / 1000000,
      sourceOffsetSeconds:
          (clip.sourceOffsetSeconds ?? 0) + (leftDurationUs / 1000000),
      splitGroupId: splitGroupId,
      filmstripReferenceOffsetSeconds: referenceOffsetSeconds,
      filmstripReferenceDurationSeconds: referenceDurationSeconds,
    );

    final nextClips = List<TimelineClipData>.from(_videoTimelineClips)
      ..removeAt(location.index)
      ..insertAll(location.index, <TimelineClipData>[leftClip, rightClip]);

    if (!mounted) {
      return;
    }
    setState(() {
      _videoTimelineClips = List<TimelineClipData>.unmodifiable(nextClips);
      _tracks = _buildPhaseOneTracks();
      _selectedClipId = rightClip.id;
    });
  }

  bool get _canDeleteSelectedClip =>
      _selectedClipId != null && _resolveSelectedClipIndex() != null;

  int? _resolveSelectedClipIndex() {
    final selectedClipId = _selectedClipId;
    if (selectedClipId == null) {
      return null;
    }
    final index =
        _videoTimelineClips.indexWhere((clip) => clip.id == selectedClipId);
    return index >= 0 ? index : null;
  }

  Future<void> _deleteSelectedClip() async {
    final selectedIndex = _resolveSelectedClipIndex();
    if (selectedIndex == null || _videoTimelineClips.isEmpty) {
      return;
    }
    if (_videoTimelineClips.length == 1) {
      if (_isPlaying && _canUseNativePlayback) {
        await _engineBridge.dispatch(
          const FusionXEngineCommand(
            type: FusionXEngineCommandType.pause,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAssetId = null;
        _selectedClipId = null;
        _playbackStatus = FusionXTransportState.ready.name;
        _lastError = null;
        _firstFrameRendered = false;
        _sourceDurationUs = 0;
        _trimStartUs = 0;
        _trimEndUs = 0;
        _sourceTimeUs = 0;
        _timelineTimeUs = 0;
        _nativeScrubReady = false;
        _activeScrubTimelineTimeUs = null;
        _stableScrubTimelineTimeUs = null;
        _pendingScrubTimelineTimeUs = null;
        _videoTimelineClips = const <TimelineClipData>[];
        _tracks = _buildPhaseOneTracks();
      });
      _previewTimelineTimeUs.value = 0;
      return;
    }
    if (_videoTimelineClips.length != 2) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Delete is currently wired for the two split halves of one clip.',
          ),
        ),
      );
      return;
    }
    if (_isTimelineScrubSettling) {
      await _completeTimelineScrub();
    }
    final remainingIndex = selectedIndex == 0 ? 1 : 0;
    final remainingClip = _videoTimelineClips[remainingIndex];
    final nextTrimStartUs =
        ((remainingClip.sourceOffsetSeconds ?? 0) * 1000000).round();
    final nextTrimEndUs =
        (((remainingClip.sourceOffsetSeconds ?? 0) + remainingClip.duration) *
                1000000)
            .round();
    final nextDurationUs = nextTrimEndUs - nextTrimStartUs;
    final nextTimelineTimeUs = selectedIndex == 0
        ? (_timelineTimeUs - (_videoTimelineClips.first.duration * 1000000).round())
            .clamp(0, nextDurationUs)
        : _timelineTimeUs.clamp(0, nextDurationUs);

    if (!mounted) {
      return;
    }
    setState(() {
      _trimStartUs = nextTrimStartUs;
      _trimEndUs = nextTrimEndUs;
      _timelineTimeUs = nextTimelineTimeUs;
      _sourceTimeUs = nextTrimStartUs + nextTimelineTimeUs;
      _videoTimelineClips = <TimelineClipData>[
        TimelineClipData(
          id: _primaryClipId,
          duration: nextDurationUs / 1000000,
          type: TimelineClipType.media,
          tone: TimelineClipTone.hero,
          assetId: remainingClip.assetId,
          label: remainingClip.label,
          sourceOffsetSeconds: nextTrimStartUs / 1000000,
          filmstripReferenceOffsetSeconds: nextTrimStartUs / 1000000,
          filmstripReferenceDurationSeconds: nextDurationUs / 1000000,
        ),
      ];
      _tracks = _buildPhaseOneTracks();
      _selectedClipId = _primaryClipId;
    });
    _previewTimelineTimeUs.value = nextTimelineTimeUs;

    if (_canUseNativePlayback) {
      await _engineBridge.dispatch(
        FusionXEngineCommand(
          type: FusionXEngineCommandType.setTrim,
          payload: SetTrimPayload(
            trimStartUs: nextTrimStartUs,
            trimEndUs: nextTrimEndUs,
          ).toMap(),
        ),
      );
    }
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
                      textureId: _textureId,
                      currentSecondsListenable: _previewTimelineTimeUs,
                      isAndroidFoundationSupported:
                          _isAndroidFoundationSupported,
                      renderTargetAttached: _renderTargetAttached,
                      engineAvailable: _engineAvailable,
                      hasClip: _hasClip,
                      playbackStatus: _playbackStatus,
                      firstFrameRendered: _firstFrameRendered,
                      lastError: _lastError,
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
                          onSplit: _hasClip && _canSplitAtCurrentTime
                              ? () {
                                  unawaited(_splitSelectedClip());
                                }
                              : null,
                          onTrimRight:
                              _videoTimelineClips.length == 1 &&
                                      _selectedClipId == _primaryClipId
                              ? _trimSelectedClipRight
                              : null,
                          onTrimLeft:
                              _videoTimelineClips.length == 1 &&
                                      _selectedClipId == _primaryClipId
                              ? _trimSelectedClipLeft
                              : null,
                          onDuplicate: null,
                          onDelete: _canDeleteSelectedClip
                              ? () {
                                  unawaited(_deleteSelectedClip());
                                }
                              : null,
                          onPlayToggle: _hasClip
                              ? () {
                                  unawaited(_togglePlayback());
                                }
                              : null,
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
                            currentTimeUsListenable: _previewTimelineTimeUs,
                            timelineDuration: _timelineDuration,
                            isPlaying: _isPlaying,
                            selectedClipId: _selectedClipId,
                            onTimeChanged: _setCurrentSeconds,
                            onClipSelected: _selectClip,
                            onClipReorder: null,
                            onBackgroundTap: _clearSelection,
                            assetPathResolver: _resolveAssetPath,
                            assetThumbnailResolver: _resolveAssetThumbnail,
                            onScrubStateChanged:
                                _handleTimelineScrubStateChanged,
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
                          onAddTap: () {
                            unawaited(_openMediaSheet(EditorMediaTab.video));
                          },
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

class _TimelineClipLocation {
  const _TimelineClipLocation({
    required this.clip,
    required this.index,
    required this.timelineStartUs,
    required this.durationUs,
    required this.relativeCutUs,
  });

  final TimelineClipData clip;
  final int index;
  final int timelineStartUs;
  final int durationUs;
  final int relativeCutUs;
}

class _CleanPreviewCanvas extends StatelessWidget {
  const _CleanPreviewCanvas({
    required this.asset,
    required this.textureId,
    required this.currentSecondsListenable,
    required this.isAndroidFoundationSupported,
    required this.renderTargetAttached,
    required this.engineAvailable,
    required this.hasClip,
    required this.playbackStatus,
    required this.firstFrameRendered,
    required this.lastError,
  });

  final MockAssetItem? asset;
  final int? textureId;
  final ValueListenable<int> currentSecondsListenable;
  final bool isAndroidFoundationSupported;
  final bool renderTargetAttached;
  final bool engineAvailable;
  final bool hasClip;
  final String playbackStatus;
  final bool firstFrameRendered;
  final String? lastError;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (textureId != null && textureId! >= 0 && asset != null)
              Texture(textureId: textureId!),
            if (asset == null || !firstFrameRendered)
              _CanvasMessage(
                title: _title,
                body: _body,
              ),
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.46),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: Text(
                  asset?.label ?? 'FusionX Native Preview',
                  style: const TextStyle(
                    color: FxPalette.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: ValueListenableBuilder<int>(
                valueListenable: currentSecondsListenable,
                builder: (context, currentTimeUs, _) {
                  final currentSeconds = currentTimeUs / 1000000;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Time ${currentSeconds.toStringAsFixed(2)}s',
                        style: const TextStyle(
                          color: FxPalette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        playbackStatus,
                        style: const TextStyle(
                          color: FxPalette.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _title {
    if (!isAndroidFoundationSupported) {
      return 'Android only';
    }
    if (!engineAvailable) {
      return 'Native bridge unavailable';
    }
    if (!renderTargetAttached) {
      return 'Preparing surface';
    }
    if (asset == null) {
      return 'Import a video';
    }
    if (playbackStatus == FusionXTransportState.error.name) {
      return 'Preview failed';
    }
    return 'Loading first frame';
  }

  String get _body {
    if (!isAndroidFoundationSupported) {
      return 'Phase 1 native playback is wired for Android first.';
    }
    if (!engineAvailable) {
      return lastError ??
          'The native playback foundation could not be attached here.';
    }
    if (!renderTargetAttached) {
      return 'Attaching the native preview surface...';
    }
    if (asset == null) {
      return 'Use the + button to import a real local video into the original editor UI.';
    }
    if (playbackStatus == FusionXTransportState.error.name) {
      return lastError ??
          'The native preview pipeline reported an error before rendering the first frame.';
    }
    return 'The selected clip is being prepared inside the native preview pipeline.';
  }
}

class _CanvasMessage extends StatelessWidget {
  const _CanvasMessage({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxWidth < 160 || constraints.maxHeight < 220;
        return Center(
          child: SingleChildScrollView(
            primary: false,
            padding: EdgeInsets.all(isCompact ? 14 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smart_display_rounded,
                    size: isCompact ? 28 : 40,
                    color: FxPalette.textPrimary,
                  ),
                  SizedBox(height: isCompact ? 8 : 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: isCompact
                        ? Theme.of(context).textTheme.bodyMedium
                        : Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: isCompact ? 6 : 8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
