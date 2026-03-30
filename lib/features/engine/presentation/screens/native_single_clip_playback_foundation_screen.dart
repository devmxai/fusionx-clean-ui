import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../engine/bridge/fusionx_debug_picker.dart';
import '../../../../engine/bridge/method_channel_fusionx_engine_bridge.dart';
import '../../../../engine/contracts/engine_contracts.dart';
import '../../../../engine/models/engine_time.dart';

class NativeSingleClipPlaybackFoundationScreen extends StatefulWidget {
  const NativeSingleClipPlaybackFoundationScreen({super.key});

  @override
  State<NativeSingleClipPlaybackFoundationScreen> createState() =>
      _NativeSingleClipPlaybackFoundationScreenState();
}

class _NativeSingleClipPlaybackFoundationScreenState
    extends State<NativeSingleClipPlaybackFoundationScreen> {
  final MethodChannelFusionXEngineBridge _engineBridge =
      MethodChannelFusionXEngineBridge();
  final FusionXDebugPicker _debugPicker = FusionXDebugPicker();

  StreamSubscription<FusionXEngineEvent>? _eventsSubscription;

  int? _textureId;
  String? _clipPath;
  String _status = 'idle';
  String? _lastError;
  int _sourceDurationUs = 0;
  int _trimStartUs = 0;
  int _trimEndUs = 0;
  int _sourceTimeUs = 0;
  int _timelineTimeUs = 0;
  int _pendingSeekUs = 0;
  RangeValues _trimValues = const RangeValues(0, 1);
  bool _renderTargetAttached = false;
  bool _firstFrameRendered = false;
  bool _trimDirty = false;

  bool get _isAndroidFoundationSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _hasClip => _clipPath != null && _sourceDurationUs > 0;

  bool get _isPlaying => _status == FusionXTransportState.playing.name;

  int get _clipDurationUs =>
      (_trimEndUs - _trimStartUs).clamp(0, _sourceDurationUs);

  bool get _trimIsActive =>
      _hasClip && (_trimStartUs > 0 || _trimEndUs < _sourceDurationUs);

  @override
  void initState() {
    super.initState();
    _eventsSubscription = _engineBridge.events.listen(_handleEngineEvent);
    unawaited(_initializeFoundation());
  }

  Future<void> _initializeFoundation() async {
    if (!_isAndroidFoundationSupported) {
      return;
    }
    await _engineBridge.initialize();
    final result = await _engineBridge.attachRenderTarget(
      width: 720,
      height: 1280,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _textureId = result.textureId;
      _renderTargetAttached = result.textureId >= 0;
      _status = 'ready';
    });
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
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
    super.dispose();
  }

  void _handleEngineEvent(FusionXEngineEvent event) {
    if (!mounted) {
      return;
    }

    switch (event.type) {
      case FusionXEngineEventType.ready:
        setState(() {
          _status = 'ready';
        });
      case FusionXEngineEventType.durationResolved:
        final sourceDurationUs =
            (event.payload['sourceDurationUs'] as num?)?.toInt() ?? 0;
        final trimStartUs =
            (event.payload['trimStartUs'] as num?)?.toInt() ?? 0;
        final trimEndUs =
            (event.payload['trimEndUs'] as num?)?.toInt() ?? sourceDurationUs;
        setState(() {
          _sourceDurationUs = sourceDurationUs;
          _trimStartUs = trimStartUs;
          _trimEndUs = trimEndUs;
          _trimValues = RangeValues(
            trimStartUs.toDouble(),
            trimEndUs.toDouble().clamp(trimStartUs.toDouble(), _sliderMaxValue),
          );
          if (!_trimDirty) {
            _pendingSeekUs = _timelineTimeUs;
          }
        });
      case FusionXEngineEventType.positionChanged:
        final sourceTimeUs =
            (event.payload['sourceTimeUs'] as num?)?.toInt() ?? _sourceTimeUs;
        final timelineTimeUs =
            (event.payload['timelineTimeUs'] as num?)?.toInt() ?? 0;
        setState(() {
          _sourceTimeUs = sourceTimeUs;
          _timelineTimeUs = timelineTimeUs;
          if (!_trimDirty) {
            _pendingSeekUs = timelineTimeUs;
          }
        });
      case FusionXEngineEventType.playbackStateChanged:
        final state = event.payload['state'] as String? ?? 'idle';
        setState(() {
          _status = state;
        });
      case FusionXEngineEventType.firstFrameRendered:
        setState(() {
          _firstFrameRendered = true;
        });
      case FusionXEngineEventType.scrubFrameAvailable:
        break;
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
          _pendingSeekUs = 0;
          _trimValues = RangeValues(
            trimStartUs.toDouble(),
            trimEndUs.toDouble().clamp(trimStartUs.toDouble(), _sliderMaxValue),
          );
          _trimDirty = false;
        });
      case FusionXEngineEventType.error:
        setState(() {
          _lastError = event.payload['message'] as String? ?? 'Unknown error';
          _status = 'error';
        });
    }
  }

  double get _sliderMaxValue =>
      _sourceDurationUs <= 0 ? 1 : _sourceDurationUs.toDouble();

  Future<void> _pickAndLoadClip() async {
    if (!_isAndroidFoundationSupported) {
      return;
    }
    final path = await _debugPicker.pickVideoClip();
    if (!mounted || path == null || path.isEmpty) {
      return;
    }
    setState(() {
      _clipPath = path;
      _lastError = null;
      _status = 'loading';
      _sourceTimeUs = 0;
      _timelineTimeUs = 0;
      _pendingSeekUs = 0;
      _firstFrameRendered = false;
    });
    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: FusionXEngineCommandType.loadClip,
        payload: LoadClipPayload(path: path).toMap(),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (!_hasClip) {
      return;
    }
    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: _isPlaying
            ? FusionXEngineCommandType.pause
            : FusionXEngineCommandType.play,
      ),
    );
  }

  Future<void> _applySeek(double value) async {
    if (!_hasClip) {
      return;
    }
    final targetUs = value.round();
    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: FusionXEngineCommandType.seekTo,
        payload: SeekToPayload(
          timelineTime: EngineTime.fromMicroseconds(targetUs),
        ).toMap(),
      ),
    );
  }

  Future<void> _applyTrim(RangeValues values) async {
    if (!_hasClip) {
      return;
    }
    final trimStartUs = values.start.round();
    final trimEndUs =
        values.end.round().clamp(trimStartUs + 1, _sourceDurationUs);
    await _engineBridge.dispatch(
      FusionXEngineCommand(
        type: FusionXEngineCommandType.setTrim,
        payload: SetTrimPayload(
          trimStartUs: trimStartUs,
          trimEndUs: trimEndUs,
        ).toMap(),
      ),
    );
  }

  String _formatUs(int value) {
    final totalSeconds = value / 1000000;
    return '${totalSeconds.toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final canInteract = _isAndroidFoundationSupported && _renderTargetAttached;
    final timelineMax = (_trimEndUs - _trimStartUs)
        .clamp(1, _sourceDurationUs == 0 ? 1 : _sourceDurationUs);
    final seekValue = _pendingSeekUs.clamp(0, timelineMax).toDouble();

    return Scaffold(
      backgroundColor: FxPalette.background,
      appBar: AppBar(
        title: const Text('FusionX Clean UI'),
        backgroundColor: FxPalette.background,
        foregroundColor: FxPalette.textPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Engine V1 · Native Single-Clip Playback Foundation',
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: FxPalette.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: FxPalette.divider, width: 1),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    FxPalette.previewTop,
                                    FxPalette.previewBottom,
                                  ],
                                ),
                              ),
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 9 / 16,
                                  child: _buildPreviewSurface(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SingleChildScrollView(
                            primary: false,
                            child: _buildStatusCard(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: canInteract ? _pickAndLoadClip : null,
                          child: const Text('Load Clip'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _hasClip ? _togglePlayback : null,
                          child: Text(_isPlaying ? 'Pause' : 'Play'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSeekControls(
                      context, seekValue, timelineMax.toDouble()),
                  const SizedBox(height: 12),
                  _buildTrimControls(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSurface() {
    if (!_isAndroidFoundationSupported) {
      return const _PreviewMessage(
        title: 'Android only',
        body:
            'Phase 1 native playback foundation is currently wired for Android only.',
      );
    }
    if (_textureId == null || _textureId! < 0) {
      return const _PreviewMessage(
        title: 'Preparing surface',
        body: 'Attaching native render target...',
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Texture(textureId: _textureId!),
        if (!_hasClip)
          const _PreviewMessage(
            title: 'Load a clip',
            body:
                'Choose a local MP4 to verify first frame, play, pause, seek, and trim.',
          ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FusionX Clean UI',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Status: $_status'),
          const SizedBox(height: 4),
          Text('First frame: ${_firstFrameRendered ? 'ready' : 'pending'}'),
          const SizedBox(height: 4),
          Text(
            'Clip: ${_clipPath ?? 'No clip loaded'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Source: ${_formatUs(_sourceTimeUs)} / ${_formatUs(_sourceDurationUs)}',
          ),
          const SizedBox(height: 4),
          Text(
            'Timeline: ${_formatUs(_timelineTimeUs)} / ${_formatUs(_clipDurationUs)}',
          ),
          const SizedBox(height: 4),
          Text(
            'Trim: ${_formatUs(_trimStartUs)} -> ${_formatUs(_trimEndUs)}'
            '${_trimIsActive ? ' (active)' : ''}',
          ),
          const SizedBox(height: 8),
          Text(
            _trimIsActive
                ? 'Playback restarts from the selected in-point and stops at the out-point.'
                : 'Move the trim handles to define the playback window before testing play.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Error: $_lastError',
              style: const TextStyle(color: FxPalette.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeekControls(
    BuildContext context,
    double seekValue,
    double maxValue,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Seek',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Slider(
          value: seekValue.clamp(0, maxValue),
          min: 0,
          max: maxValue <= 0 ? 1 : maxValue,
          onChanged: _hasClip
              ? (value) {
                  setState(() {
                    _pendingSeekUs = value.round();
                  });
                }
              : null,
          onChangeEnd: _hasClip ? _applySeek : null,
        ),
      ],
    );
  }

  Widget _buildTrimControls(BuildContext context) {
    final values = RangeValues(
      _trimValues.start.clamp(0, _sliderMaxValue),
      _trimValues.end.clamp(0, _sliderMaxValue),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trim Window',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        RangeSlider(
          values: values,
          min: 0,
          max: _sliderMaxValue,
          onChanged: _hasClip
              ? (nextValues) {
                  setState(() {
                    _trimDirty = true;
                    _trimValues = nextValues;
                  });
                }
              : null,
          onChangeEnd: _hasClip ? _applyTrim : null,
        ),
        const SizedBox(height: 4),
        Text(
          'Start: ${_formatUs(values.start.round())}  End: ${_formatUs(values.end.round())}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Move the left handle to set the trim start and the right handle to set the trim end.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.smart_display_rounded,
              size: 42,
              color: FxPalette.textPrimary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
