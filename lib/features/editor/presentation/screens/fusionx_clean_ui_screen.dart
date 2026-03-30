import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  static const String _primaryClipId = 'clip-primary';
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
  Future<void>? _scrubDispatchLoop;
  Future<void>? _timelineScrubCompletionTask;
  int? _pendingScrubTimelineTimeUs;
  bool _nativeScrubReady = false;

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

  double get _timelineDuration => _hasClip
      ? math.max(0.25, (_trimEndUs - _trimStartUs) / 1000000).toDouble()
      : 12;

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
    _tracks = _buildPhaseOneTracks();
    _eventsSubscription = _engineBridge.events.listen(_handleEngineEvent);
    unawaited(_initializeFoundation());
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _pendingScrubTimelineTimeUs = null;
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
          _tracks = _buildPhaseOneTracks();
          _selectedClipId = _hasClip ? _primaryClipId : null;
        });
        _previewTimelineTimeUs.value = 0;
      case FusionXEngineEventType.positionChanged:
        final sourceTimeUs =
            (event.payload['sourceTimeUs'] as num?)?.toInt() ?? _sourceTimeUs;
        final timelineTimeUs =
            (event.payload['timelineTimeUs'] as num?)?.toInt() ?? 0;
        final canAcceptTimelineUpdate = !_isTimelineScrubbing &&
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
          _tracks = _buildPhaseOneTracks();
          _selectedClipId = _hasClip ? _primaryClipId : null;
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

  List<TimelineTrackData> _buildPhaseOneTracks() {
    final selectedAsset = _selectedAsset;
    final clipDurationSeconds = (_trimEndUs - _trimStartUs) / 1000000;
    if (selectedAsset == null || clipDurationSeconds <= 0) {
      return const <TimelineTrackData>[
        TimelineTrackData(
          kind: TimelineTrackKind.video,
          clips: <TimelineClipData>[],
        ),
      ];
    }

    return <TimelineTrackData>[
      TimelineTrackData(
        kind: TimelineTrackKind.video,
        clips: <TimelineClipData>[
          TimelineClipData(
            id: _primaryClipId,
            duration: math.max(0.25, clipDurationSeconds).toDouble(),
            type: TimelineClipType.media,
            tone: TimelineClipTone.hero,
            assetId: selectedAsset.id,
            label: selectedAsset.label,
            sourceOffsetSeconds: _trimStartUs / 1000000,
          ),
        ],
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
    final asset = existingAsset ?? _buildImportedVideoAsset(item);
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
    if (_pendingScrubTimelineTimeUs != null && _scrubDispatchLoop == null) {
      _scrubDispatchLoop = _drainScrubDispatchLoop();
    }
  }

  Future<void> _endNativeScrub() async {
    if (!_hasClip || !_canUseNativePlayback) {
      return;
    }
    _queueScrubDispatch(_timelineTimeUs);
    await _flushPendingScrubDispatches();
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
    try {
      await _endNativeScrub();
    } finally {
      if (mounted) {
        setState(() {
          _isTimelineScrubSettling = false;
        });
        _previewTimelineTimeUs.value = _timelineTimeUs;
      }
    }
  }

  void _queueScrubDispatch(int timelineTimeUs) {
    _pendingScrubTimelineTimeUs = timelineTimeUs;
    if (!_nativeScrubReady) {
      return;
    }
    _scrubDispatchLoop ??= _drainScrubDispatchLoop();
  }

  Future<void> _flushPendingScrubDispatches() async {
    while (true) {
      final activeLoop = _scrubDispatchLoop;
      if (activeLoop == null) {
        return;
      }
      await activeLoop;
    }
  }

  Future<void> _drainScrubDispatchLoop() async {
    try {
      while (mounted) {
        final nextTimelineTimeUs = _pendingScrubTimelineTimeUs;
        if (nextTimelineTimeUs == null) {
          break;
        }
        _pendingScrubTimelineTimeUs = null;
        await _engineBridge.dispatch(
          FusionXEngineCommand(
            type: FusionXEngineCommandType.scrubTo,
            payload: SeekToPayload(
              timelineTime: EngineTime.fromMicroseconds(nextTimelineTimeUs),
            ).toMap(),
          ),
        );
      }
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
    } finally {
      _scrubDispatchLoop = null;
      if (mounted && _pendingScrubTimelineTimeUs != null) {
        _scrubDispatchLoop = _drainScrubDispatchLoop();
      }
    }
  }

  void _setCurrentSeconds(double seconds) {
    final clampedSeconds = seconds.clamp(0.0, _timelineDuration).toDouble();
    final timelineTimeUs = (clampedSeconds * 1000000).round();
    _timelineTimeUs = timelineTimeUs;
    _previewTimelineTimeUs.value = timelineTimeUs;
    if (!_hasClip || !_canUseNativePlayback) {
      return;
    }
    if (_isTimelineScrubbing) {
      _queueScrubDispatch(timelineTimeUs);
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

  void _handleTimelineScrubStateChanged(bool isScrubbing) {
    if (_isTimelineScrubbing == isScrubbing) {
      return;
    }
    setState(() {
      _isTimelineScrubbing = isScrubbing;
      if (isScrubbing) {
        _isTimelineScrubSettling = false;
      } else if (_hasClip && _canUseNativePlayback) {
        _isTimelineScrubSettling = true;
      }
    });
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
    if (clipId != _primaryClipId) {
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
                          onSplit: null,
                          onTrimRight: _selectedClipId == _primaryClipId
                              ? _trimSelectedClipRight
                              : null,
                          onTrimLeft: _selectedClipId == _primaryClipId
                              ? _trimSelectedClipLeft
                              : null,
                          onDuplicate: null,
                          onDelete: null,
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
            if (textureId != null && textureId! >= 0 && hasClip)
              Texture(textureId: textureId!),
            if (!hasClip || !firstFrameRendered)
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
    if (!hasClip) {
      return 'Import a video';
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
    if (!hasClip) {
      return 'Use the + button to import a real local video into the original editor UI.';
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
