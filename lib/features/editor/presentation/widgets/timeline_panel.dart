import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/media/native_media_thumbnailer.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/timeline_mock_models.dart';

typedef TimelineAssetPathResolver = String? Function(String assetId);
typedef TimelineAssetThumbnailResolver = Uint8List? Function(String assetId);
typedef TimelineClipReorderCallback = void Function(
  String clipId,
  int insertionIndex,
);

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    this.embedded = false,
    required this.tracks,
    required this.currentTimeUsListenable,
    required this.timelineDuration,
    required this.isPlaying,
    required this.selectedClipId,
    required this.onTimeChanged,
    required this.onClipSelected,
    this.onClipReorder,
    this.onBackgroundTap,
    this.assetPathResolver,
    this.assetThumbnailResolver,
    this.onScrubStateChanged,
  });

  final bool embedded;
  final List<TimelineTrackData> tracks;
  final ValueListenable<int> currentTimeUsListenable;
  final double timelineDuration;
  final bool isPlaying;
  final String? selectedClipId;
  final ValueChanged<double> onTimeChanged;
  final ValueChanged<String> onClipSelected;
  final TimelineClipReorderCallback? onClipReorder;
  final VoidCallback? onBackgroundTap;
  final TimelineAssetPathResolver? assetPathResolver;
  final TimelineAssetThumbnailResolver? assetThumbnailResolver;
  final ValueChanged<bool>? onScrubStateChanged;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel>
    with SingleTickerProviderStateMixin {
  static const double _panelPadding = 8;
  static const double _rowHeight = 38;
  static const double _rowGap = 6;
  static const double _controlTileSize = 36;
  static const double _controlGap = 6;
  static const double _splitGap = 0;
  static const double _trailingPadding = 120;
  static const double _timeReadoutWidth = 96;
  static const double _minSecondsWidth = 14;
  static const double _maxSecondsWidth = 1800;
  static const double _timelineFps = 30;
  static const double _framePrecisionSecondsWidth = 280;
  static const double _reorderCardHeight = 36;
  static const double _reorderCardWidth = 40;
  static const double _reorderBaseSlotWidth = 8;
  static const double _reorderActiveSlotWidth = 26;
  static const double _reorderEdgePadding = 12;
  static const double _reorderTrailingPadding = 40;
  static const Duration _reorderExitDelay = Duration(milliseconds: 180);
  static const double _minScrubFlingVelocityPxPerSecond = 64;
  static const double _maxScrubFlingVelocityPxPerSecond = 4800;
  static const double _scrubFlingDecelerationPxPerSecondSquared = 5600;
  static const double _minScrubFlingDistancePx = 18;
  static const double _scrubFlingSettleVelocityPxPerSecond = 22;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  double _playheadLeft = 0;
  double _leadingOffset = 0;
  double _secondsWidth = 118;
  double _scaleStartSecondsWidth = 118;
  double _scaleStartFocusTime = 0;
  double _scaleStartLocalFocalX = 0;
  bool _isSyncingFromExternal = false;
  bool _isScrollActive = false;
  bool _isBackgroundScrubbing = false;
  bool _isScrubInteractionActive = false;
  final Set<int> _activePointers = <int>{};
  int? _primaryPointerId;
  double? _scrubAnchorPointerX;
  double _scrubAnchorSeconds = 0;
  double _rawScrubDx = 0;
  double _rawScrubDy = 0;
  bool _rawScrubLocked = false;
  int _lastScrubDirectionSign = 0;
  double? _pendingSeconds;
  Timer? _scrollDispatchTimer;
  DateTime? _lastDispatchedAt;
  List<TimelineTrackData>? _reorderTracksSnapshot;
  int? _reorderTrackIndex;
  String? _draggedClipId;
  int? _hoverInsertionIndex;
  double _dragOffset = 0;
  double _dragStartOffset = 0;
  double _dragCardWidth = 0;
  bool _isDropSettling = false;
  Timer? _reorderExitTimer;
  double _backgroundScrubCurrentSeconds = 0;
  int _externalCurrentTimeUs = 0;
  late final AnimationController _scrubFlingController;
  VelocityTracker? _scrubVelocityTracker;
  bool _isBackgroundFlinging = false;

  bool get _isReorderMode =>
      _reorderTracksSnapshot != null &&
      _reorderTrackIndex != null &&
      _draggedClipId != null;

  @override
  void initState() {
    super.initState();
    _scrubFlingController = AnimationController.unbounded(vsync: this)
      ..addListener(_handleScrubFlingTick);
    _externalCurrentTimeUs = widget.currentTimeUsListenable.value;
    widget.currentTimeUsListenable.addListener(_handleExternalCurrentTimeChanged);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant TimelinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTimeUsListenable != widget.currentTimeUsListenable) {
      oldWidget.currentTimeUsListenable
          .removeListener(_handleExternalCurrentTimeChanged);
      _externalCurrentTimeUs = widget.currentTimeUsListenable.value;
      widget.currentTimeUsListenable.addListener(_handleExternalCurrentTimeChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToTime());
    } else if (oldWidget.isPlaying != widget.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToTime());
    }
  }

  @override
  void dispose() {
    widget.currentTimeUsListenable
        .removeListener(_handleExternalCurrentTimeChanged);
    _scrollController.removeListener(_handleScroll);
    _scrollDispatchTimer?.cancel();
    _reorderExitTimer?.cancel();
    _scrubFlingController
      ..removeListener(_handleScrubFlingTick)
      ..dispose();
    _scrollController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  double get _externalCurrentSeconds => _externalCurrentTimeUs / 1000000;

  void _handleExternalCurrentTimeChanged() {
    final nextTimeUs = widget.currentTimeUsListenable.value;
    if (nextTimeUs == _externalCurrentTimeUs) {
      return;
    }
    _externalCurrentTimeUs = nextTimeUs;
    if (!mounted) {
      return;
    }
    if (_isBackgroundScrubbing) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToTime());
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (_isReorderMode) {
      return;
    }
    _scaleStartSecondsWidth = _secondsWidth;
    _scaleStartLocalFocalX = details.localFocalPoint.dx;
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final focalTimelineOffset = (scrollOffset + _scaleStartLocalFocalX - _playheadLeft)
        .clamp(0.0, widget.timelineDuration * _secondsWidth)
        .toDouble();
    _scaleStartFocusTime = (focalTimelineOffset / _secondsWidth)
        .clamp(0.0, widget.timelineDuration)
        .toDouble();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_isReorderMode) {
      return;
    }
    if (details.pointerCount < 2) {
      return;
    }

    final nextWidth = (_scaleStartSecondsWidth * details.scale)
        .clamp(_minSecondsWidth, _maxSecondsWidth)
        .toDouble();

    if ((nextWidth - _secondsWidth).abs() < 0.5) {
      return;
    }

    setState(() {
      _secondsWidth = nextWidth;
    });

    final nextScrollOffset = ((_scaleStartFocusTime * _secondsWidth) -
            _scaleStartLocalFocalX +
            _playheadLeft)
        .clamp(0.0, math.max(0.0, widget.timelineDuration * _secondsWidth))
        .toDouble();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final nextOffset = nextScrollOffset
          .clamp(0, _scrollController.position.maxScrollExtent)
          .toDouble();
      _isSyncingFromExternal = true;
      _scrollController.jumpTo(nextOffset);
      _isSyncingFromExternal = false;
    });
  }

  void _handleScroll() {
    if (_isReorderMode) {
      return;
    }
    if (_isSyncingFromExternal) {
      return;
    }

    final offset = _scrollController.hasClients
        ? _scrollController.offset.clamp(0, double.infinity)
        : 0.0;
    final nextSeconds =
        (offset / _secondsWidth).clamp(0, widget.timelineDuration).toDouble();

    _dispatchTimelineSeconds(nextSeconds);
  }

  void _flushPendingScrollSeconds() {
    _scrollDispatchTimer?.cancel();
    _scrollDispatchTimer = null;
    final nextSeconds = _pendingSeconds;
    _pendingSeconds = null;
    if (nextSeconds == null) {
      return;
    }
    _lastDispatchedAt = DateTime.now();
    widget.onTimeChanged(nextSeconds);
  }

  void _dispatchTimelineSeconds(double nextSeconds) {
    if (_isScrubInteractionActive || _isBackgroundScrubbing) {
      _scrollDispatchTimer?.cancel();
      _scrollDispatchTimer = null;
      _pendingSeconds = null;
      _lastDispatchedAt = DateTime.now();
      widget.onTimeChanged(nextSeconds);
      return;
    }

    if ((nextSeconds - _externalCurrentSeconds).abs() <= 0.002 &&
        _pendingSeconds == null) {
      return;
    }

    final now = DateTime.now();
    if (_lastDispatchedAt == null ||
        now.difference(_lastDispatchedAt!) >=
            const Duration(milliseconds: 16)) {
      _lastDispatchedAt = now;
      widget.onTimeChanged(nextSeconds);
      return;
    }

    _pendingSeconds = nextSeconds;
    _scrollDispatchTimer ??=
        Timer(const Duration(milliseconds: 16), _flushPendingScrollSeconds);
  }

  void _setScrubInteractionActive(bool isActive) {
    if (_isScrubInteractionActive == isActive) {
      return;
    }
    _isScrubInteractionActive = isActive;
    widget.onScrubStateChanged?.call(isActive);
  }

  void _beginBackgroundScrub() {
    if (_isReorderMode) {
      return;
    }
    _cancelBackgroundScrubFling();
    if (_isBackgroundScrubbing) {
      return;
    }
    setState(() {
      _backgroundScrubCurrentSeconds = _externalCurrentSeconds;
      _isBackgroundScrubbing = true;
    });
    _scrubAnchorSeconds = _externalCurrentSeconds;
    _lastScrubDirectionSign = 0;
    _setScrubInteractionActive(true);
  }

  void _applyBackgroundScrubSeconds(double nextSeconds) {
    final clampedSeconds =
        nextSeconds.clamp(0.0, widget.timelineDuration).toDouble();
    setState(() {
      _backgroundScrubCurrentSeconds = clampedSeconds;
    });

    if (_scrollController.hasClients) {
      final targetOffset = (clampedSeconds * _secondsWidth)
          .clamp(0.0, _scrollController.position.maxScrollExtent)
          .toDouble();
      _isSyncingFromExternal = true;
      _scrollController.jumpTo(targetOffset);
      _isSyncingFromExternal = false;
    }

    _dispatchTimelineSeconds(clampedSeconds);
  }

  void _updateBackgroundScrub(PointerMoveEvent event) {
    if (_isReorderMode || !_isBackgroundScrubbing) {
      return;
    }
    final anchorX = _scrubAnchorPointerX ?? event.localPosition.dx;
    final pointerDeltaDx = event.localPosition.dx - anchorX;

    final nextSeconds =
        (_scrubAnchorSeconds - (pointerDeltaDx / _secondsWidth))
            .clamp(0.0, widget.timelineDuration)
            .toDouble();
    _applyBackgroundScrubSeconds(nextSeconds);
  }

  void _endBackgroundScrub() {
    if (!_isBackgroundScrubbing) {
      return;
    }
    _cancelBackgroundScrubFling();
    setState(() {
      _isBackgroundScrubbing = false;
    });
    _flushPendingScrollSeconds();
    _setScrubInteractionActive(_isScrollActive);
  }

  void _handleScrubFlingTick() {
    if (!_isBackgroundFlinging) {
      return;
    }
    final maxOffset = math.max(0.0, widget.timelineDuration * _secondsWidth);
    final rawOffset = _scrubFlingController.value;
    final clampedOffset = rawOffset.clamp(0.0, maxOffset).toDouble();
    _applyBackgroundScrubSeconds(clampedOffset / _secondsWidth);
    if ((rawOffset - clampedOffset).abs() > 0.5) {
      _cancelBackgroundScrubFling();
      _endBackgroundScrub();
    }
  }

  void _cancelBackgroundScrubFling() {
    _isBackgroundFlinging = false;
    if (_scrubFlingController.isAnimating) {
      _scrubFlingController.stop();
    }
  }

  bool _startBackgroundScrubFling(double pointerVelocityPxPerSecond) {
    if (!_isBackgroundScrubbing) {
      return false;
    }
    final scrollVelocityPxPerSecond = (-pointerVelocityPxPerSecond).clamp(
      -_maxScrubFlingVelocityPxPerSecond,
      _maxScrubFlingVelocityPxPerSecond,
    );
    final velocityMagnitude = scrollVelocityPxPerSecond.abs();
    if (velocityMagnitude < _minScrubFlingVelocityPxPerSecond) {
      return false;
    }

    final maxOffset = math.max(0.0, widget.timelineDuration * _secondsWidth);
    final currentOffset = (_backgroundScrubCurrentSeconds * _secondsWidth)
        .clamp(0.0, maxOffset)
        .toDouble();
    final travelDistance = math.max(
      _minScrubFlingDistancePx,
      (velocityMagnitude * velocityMagnitude) /
          (2 * _scrubFlingDecelerationPxPerSecondSquared),
    );
    final targetOffset = (currentOffset +
            (scrollVelocityPxPerSecond.sign * travelDistance))
        .clamp(0.0, maxOffset)
        .toDouble();
    final targetDelta = targetOffset - currentOffset;
    if (targetDelta.abs() < 1.0) {
      return false;
    }

    _cancelBackgroundScrubFling();
    _isBackgroundFlinging = true;
    _scrubFlingController.value = currentOffset;
    final settleVelocity =
        _scrubFlingSettleVelocityPxPerSecond * targetDelta.sign;
    final simulation = FrictionSimulation.through(
      currentOffset,
      targetOffset,
      scrollVelocityPxPerSecond,
      settleVelocity,
    );
    unawaited(
      _scrubFlingController
          .animateWith(simulation)
          .whenComplete(() {
        if (!mounted || !_isBackgroundFlinging) {
          return;
        }
        _cancelBackgroundScrubFling();
        _endBackgroundScrub();
      }),
    );
    return true;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isReorderMode) {
      return;
    }
    _cancelBackgroundScrubFling();
    _scrubVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _activePointers.add(event.pointer);
    if (_activePointers.length != 1) {
      _primaryPointerId = null;
      _rawScrubDx = 0;
      _rawScrubDy = 0;
      _rawScrubLocked = false;
      _endBackgroundScrub();
      return;
    }
    _primaryPointerId = event.pointer;
    _scrubAnchorPointerX = event.localPosition.dx;
    if (_isBackgroundScrubbing) {
      _scrubAnchorSeconds = _backgroundScrubCurrentSeconds;
    }
    _rawScrubDx = 0;
    _rawScrubDy = 0;
    _rawScrubLocked = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isReorderMode ||
        _primaryPointerId != event.pointer ||
        _activePointers.length != 1) {
      return;
    }

    _scrubVelocityTracker?.addPosition(event.timeStamp, event.position);
    _rawScrubDx += event.delta.dx.abs();
    _rawScrubDy += event.delta.dy.abs();

    if (!_rawScrubLocked) {
      if (_rawScrubDx < 1.25) {
        return;
      }
      if (_rawScrubDx <= _rawScrubDy + 0.5) {
        return;
      }
      _rawScrubLocked = true;
      _beginBackgroundScrub();
    }

    final horizontalDirectionSign = event.delta.dx == 0
        ? 0
        : (event.delta.dx > 0 ? 1 : -1);
    if (horizontalDirectionSign != 0) {
      if (_lastScrubDirectionSign != 0 &&
          horizontalDirectionSign != _lastScrubDirectionSign) {
        // Preserve the current move delta when direction flips so the first
        // reverse event does not collapse to a zero-distance scrub step.
        _scrubAnchorPointerX = event.localPosition.dx - event.delta.dx;
        _scrubAnchorSeconds = _backgroundScrubCurrentSeconds;
      }
      _lastScrubDirectionSign = horizontalDirectionSign;
    }

    _updateBackgroundScrub(event);
  }

  void _handlePointerEnd(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_primaryPointerId != event.pointer) {
      return;
    }
    final pointerVelocityPxPerSecond =
        _scrubVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;
    _primaryPointerId = null;
    _scrubAnchorPointerX = null;
    _rawScrubDx = 0;
    _rawScrubDy = 0;
    _rawScrubLocked = false;
    _lastScrubDirectionSign = 0;
    _scrubVelocityTracker = null;
    final didStartFling = event is PointerUpEvent &&
        _startBackgroundScrubFling(pointerVelocityPxPerSecond);
    if (didStartFling) {
      return;
    }
    _endBackgroundScrub();
  }

  void _syncToTime() {
    if (!_scrollController.hasClients ||
        _isScrollActive ||
        _isBackgroundScrubbing) {
      return;
    }

    final target = (_externalCurrentSeconds * _secondsWidth)
        .clamp(0, _scrollController.position.maxScrollExtent)
        .toDouble();

    if ((_scrollController.offset - target).abs() < 0.5) {
      return;
    }

    _isSyncingFromExternal = true;
    _scrollController.jumpTo(target);
    _isSyncingFromExternal = false;
  }

  List<TimelineTrackData> _cloneTracks(List<TimelineTrackData> tracks) {
    return tracks
        .map(
          (track) => track.copyWith(
            clips: List<TimelineClipData>.from(track.clips),
          ),
        )
        .toList(growable: false);
  }

  double _compactClipWidth(TimelineClipData clip) {
    if (clip.type == TimelineClipType.placeholder) {
      return 52;
    }
    return _reorderCardWidth;
  }

  _TimelineReorderRowLayout _buildReorderRowLayout(
    TimelineTrackData track, {
    String? draggedClipId,
    int? hoverInsertionIndex,
  }) {
    final stationaryClips = <TimelineClipData>[
      for (final clip in track.clips)
        if (clip.id != draggedClipId) clip,
    ];
    final clipStart =
        _leadingOffset + _controlTileSize + _controlGap + _reorderEdgePadding;
    final slotCenters = <double>[];
    final leftByClipId = <String, double>{};
    final widthByClipId = <String, double>{};
    var cursor = clipStart;

    for (var slotIndex = 0; slotIndex <= stationaryClips.length; slotIndex++) {
      final slotWidth = slotIndex == hoverInsertionIndex
          ? _reorderActiveSlotWidth
          : _reorderBaseSlotWidth;
      slotCenters.add(cursor + (slotWidth / 2));
      cursor += slotWidth;
      if (slotIndex == stationaryClips.length) {
        continue;
      }

      final clip = stationaryClips[slotIndex];
      final cardWidth = _compactClipWidth(clip);
      leftByClipId[clip.id] = cursor;
      widthByClipId[clip.id] = cardWidth;
      cursor += cardWidth;
    }

    return _TimelineReorderRowLayout(
      stationaryClips: stationaryClips,
      slotCenters: slotCenters,
      leftByClipId: leftByClipId,
      widthByClipId: widthByClipId,
      rowWidth: cursor + _reorderTrailingPadding,
    );
  }

  int _resolveHoverInsertionIndex(
    List<double> slotCenters,
    double dragCenter,
  ) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < slotCenters.length; i++) {
      final distance = (slotCenters[i] - dragCenter).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    final currentIndex = _hoverInsertionIndex;
    if (currentIndex != null && currentIndex < slotCenters.length) {
      final currentDistance = (slotCenters[currentIndex] - dragCenter).abs();
      if (nearestIndex != currentIndex &&
          nearestDistance + 12 >= currentDistance) {
        return currentIndex;
      }
    }
    return nearestIndex;
  }

  double _magnetizedDragOffset(List<double> slotCenters) {
    final hoverIndex = _hoverInsertionIndex;
    if (hoverIndex == null || hoverIndex >= slotCenters.length) {
      return _dragOffset;
    }

    final target = slotCenters[hoverIndex];
    final distance = (target - _dragOffset).abs();
    const snapRange = 58.0;
    if (distance >= snapRange) {
      return _dragOffset;
    }

    final t = Curves.easeOut.transform(1 - (distance / snapRange));
    return lerpDouble(_dragOffset, target, 0.2 + (t * 0.5)) ?? _dragOffset;
  }

  void _beginClipReorder(int trackIndex, TimelineClipData clip) {
    if (widget.onClipReorder == null ||
        widget.tracks[trackIndex].clips.length < 2) {
      return;
    }

    _reorderExitTimer?.cancel();
    final snapshotTracks = _cloneTracks(widget.tracks);
    final snapshotTrack = snapshotTracks[trackIndex];
    final originIndex =
        snapshotTrack.clips.indexWhere((candidate) => candidate.id == clip.id);
    if (originIndex < 0) {
      return;
    }

    final cardWidth = _compactClipWidth(clip);
    final layout = _buildReorderRowLayout(
      snapshotTrack,
      draggedClipId: clip.id,
      hoverInsertionIndex: originIndex,
    );
    final initialOffset = layout.slotCenters[originIndex];
    widget.onClipSelected(clip.id);
    setState(() {
      _reorderTracksSnapshot = snapshotTracks;
      _reorderTrackIndex = trackIndex;
      _draggedClipId = clip.id;
      _hoverInsertionIndex = originIndex;
      _dragCardWidth = cardWidth;
      _dragStartOffset = initialOffset;
      _dragOffset = initialOffset;
      _isDropSettling = false;
    });
  }

  void _updateClipReorder(
      int trackIndex, TimelineClipData clip, double deltaDx) {
    if (!_isReorderMode ||
        _isDropSettling ||
        _reorderTrackIndex != trackIndex ||
        _draggedClipId != clip.id) {
      return;
    }

    final tracksSnapshot = _reorderTracksSnapshot;
    if (tracksSnapshot == null) {
      return;
    }
    final layout = _buildReorderRowLayout(
      tracksSnapshot[trackIndex],
      draggedClipId: clip.id,
      hoverInsertionIndex: _hoverInsertionIndex,
    );
    final minOffset = layout.slotCenters.first;
    final maxOffset = layout.slotCenters.last;
    final nextOffset =
        (_dragStartOffset + deltaDx).clamp(minOffset, maxOffset).toDouble();
    final nextInsertionIndex =
        _resolveHoverInsertionIndex(layout.slotCenters, nextOffset);

    setState(() {
      _dragOffset = nextOffset;
      _hoverInsertionIndex = nextInsertionIndex;
    });
  }

  void _finishClipReorder(int trackIndex, TimelineClipData clip) {
    if (!_isReorderMode ||
        _reorderTrackIndex != trackIndex ||
        _draggedClipId != clip.id) {
      return;
    }

    final tracksSnapshot = _reorderTracksSnapshot;
    if (tracksSnapshot == null) {
      _clearReorderMode();
      return;
    }

    final originIndex = tracksSnapshot[trackIndex]
        .clips
        .indexWhere((candidate) => candidate.id == clip.id);
    final insertionIndex = (_hoverInsertionIndex ?? originIndex)
        .clamp(0, tracksSnapshot[trackIndex].clips.length - 1);
    final settledLayout = _buildReorderRowLayout(
      tracksSnapshot[trackIndex],
      draggedClipId: clip.id,
      hoverInsertionIndex: insertionIndex,
    );

    setState(() {
      _hoverInsertionIndex = insertionIndex;
      _dragOffset = settledLayout.slotCenters[insertionIndex];
      _isDropSettling = true;
    });

    if (originIndex != insertionIndex) {
      widget.onClipReorder?.call(clip.id, insertionIndex);
    }

    _reorderExitTimer?.cancel();
    _reorderExitTimer = Timer(_reorderExitDelay, _clearReorderMode);
  }

  void _clearReorderMode() {
    if (!_isReorderMode && !_isDropSettling) {
      return;
    }
    _reorderExitTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _reorderTracksSnapshot = null;
      _reorderTrackIndex = null;
      _draggedClipId = null;
      _hoverInsertionIndex = null;
      _dragOffset = 0;
      _dragStartOffset = 0;
      _dragCardWidth = 0;
      _isDropSettling = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToTime());
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isReorderMode || _isSyncingFromExternal) {
      return false;
    }
    if (notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    final previousState = _isScrollActive;
    if (notification is ScrollStartNotification ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle)) {
      _isScrollActive = true;
    } else if (notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle)) {
      _isScrollActive = false;
      _flushPendingScrollSeconds();
    }
    if (previousState != _isScrollActive) {
      _setScrubInteractionActive(_isScrollActive || _isBackgroundScrubbing);
    }
    return false;
  }

  String _formatClock(double value) {
    if (_secondsWidth >= _framePrecisionSecondsWidth) {
      return _formatFrameClock(value);
    }
    final totalMillis =
        (value.clamp(0, widget.timelineDuration) * 1000).round();
    final seconds = (totalMillis ~/ 1000).toString().padLeft(2, '0');
    final millis = (totalMillis % 1000).toString().padLeft(3, '0');
    return '00:$seconds.$millis';
  }

  String _formatWholeSeconds(double value) {
    if (_secondsWidth >= _framePrecisionSecondsWidth) {
      return _formatFrameClock(value, clampToTimeline: false);
    }
    final seconds = value.round().toString().padLeft(2, '0');
    return '00:$seconds';
  }

  String _formatFrameClock(double value, {bool clampToTimeline = true}) {
    final seconds = clampToTimeline
        ? value.clamp(0, widget.timelineDuration).toDouble()
        : value;
    final totalFrames = (seconds * _timelineFps).round();
    final fpsInt = _timelineFps.round();
    final wholeSeconds = totalFrames ~/ fpsInt;
    final mins = wholeSeconds ~/ 60;
    final secs = wholeSeconds % 60;
    final frames = totalFrames % fpsInt;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${frames.toString().padLeft(2, '0')}';
  }

  double get _displayedCurrentSeconds {
    if (_isBackgroundScrubbing) {
      return _backgroundScrubCurrentSeconds;
    }
    return _externalCurrentSeconds;
  }

  double _buildContentWidth(double trailingPadding) {
    final farthest = widget.tracks.fold<double>(
      0,
      (maxWidth, track) {
        var clipsWidth = 0.0;
        for (var i = 0; i < track.clips.length; i++) {
          final clip = track.clips[i];
          clipsWidth += clip.timelineWidth(_secondsWidth);
          if (i == track.clips.length - 1) {
            continue;
          }
          final next = track.clips[i + 1];
          final isSplitSibling = clip.splitGroupId != null &&
              clip.splitGroupId == next.splitGroupId;
          clipsWidth += isSplitSibling ? _splitGap : _controlGap;
        }
        return math.max(maxWidth, clipsWidth);
      },
    );

    return _leadingOffset +
        _controlTileSize +
        _controlGap +
        farthest +
        trailingPadding;
  }

  double _buildReorderContentWidth() {
    final tracks = _reorderTracksSnapshot ?? widget.tracks;
    var maxWidth = _leadingOffset +
        _controlTileSize +
        _controlGap +
        _reorderTrailingPadding;
    for (var index = 0; index < tracks.length; index++) {
      final layout = _buildReorderRowLayout(
        tracks[index],
        draggedClipId: index == _reorderTrackIndex ? _draggedClipId : null,
        hoverInsertionIndex:
            index == _reorderTrackIndex ? _hoverInsertionIndex : null,
      );
      maxWidth = math.max(maxWidth, layout.rowWidth);
    }
    return maxWidth;
  }

  Widget _buildReorderOverlay({
    required double viewportWidth,
    required double viewportHeight,
  }) {
    final tracks = _reorderTracksSnapshot ?? widget.tracks;
    final activeTrackIndex = _reorderTrackIndex;
    final draggedClipId = _draggedClipId;
    final contentWidth = _buildReorderContentWidth();
    final contentHeight = (tracks.length * _rowHeight) +
        (math.max(0, tracks.length - 1) * _rowGap);
    final maxHorizontalOffset = math.max(0.0, contentWidth - viewportWidth);
    final maxVerticalOffset = math.max(0.0, contentHeight - viewportHeight);
    final horizontalOffset = _scrollController.hasClients
        ? _scrollController.offset.clamp(0.0, maxHorizontalOffset).toDouble()
        : 0.0;
    final verticalOffset = _verticalController.hasClients
        ? _verticalController.offset.clamp(0.0, maxVerticalOffset).toDouble()
        : 0.0;
    final activeLayout = activeTrackIndex == null
        ? null
        : _buildReorderRowLayout(
            tracks[activeTrackIndex],
            draggedClipId: draggedClipId,
            hoverInsertionIndex: _hoverInsertionIndex,
          );
    final draggedCenter = activeLayout == null
        ? _dragOffset
        : _magnetizedDragOffset(activeLayout.slotCenters);

    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: FxPalette.surface.withOpacity(0.96),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(0.015),
                Colors.black.withOpacity(0.16),
              ],
            ),
          ),
          child: Transform.translate(
            offset: Offset(-horizontalOffset, -verticalOffset),
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < tracks.length; index++) ...[
                    _TimelineReorderTrackRow(
                      leadingOffset: _leadingOffset,
                      controlTileSize: _controlTileSize,
                      controlGap: _controlGap,
                      rowHeight: _rowHeight,
                      cardHeight: _reorderCardHeight,
                      track: tracks[index],
                      selectedClipId: widget.selectedClipId,
                      draggedClipId:
                          index == activeTrackIndex ? draggedClipId : null,
                      hoverInsertionIndex: index == activeTrackIndex
                          ? _hoverInsertionIndex
                          : null,
                      layout: index == activeTrackIndex && activeLayout != null
                          ? activeLayout
                          : _buildReorderRowLayout(tracks[index]),
                      draggedCenter:
                          index == activeTrackIndex ? draggedCenter : null,
                      draggedWidth:
                          index == activeTrackIndex ? _dragCardWidth : null,
                      isDropSettling:
                          index == activeTrackIndex && _isDropSettling,
                      assetPathResolver: widget.assetPathResolver,
                      assetThumbnailResolver: widget.assetThumbnailResolver,
                    ),
                    if (index != tracks.length - 1)
                      const SizedBox(height: _rowGap),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentViewportWidth = constraints.maxWidth - (_panelPadding * 2);
        _playheadLeft = math.min(contentViewportWidth * 0.46, 156);
        _leadingOffset = math.max(
          6,
          _playheadLeft - _controlTileSize - _controlGap,
        );
        final trailingPadding = math.max(
          _trailingPadding,
          contentViewportWidth - _playheadLeft + 24,
        );
        final contentWidth = _buildContentWidth(trailingPadding);

        return Container(
          padding: const EdgeInsets.fromLTRB(
            _panelPadding,
            _panelPadding,
            _panelPadding,
            10,
          ),
          decoration: BoxDecoration(
            color: widget.embedded ? Colors.transparent : FxPalette.surface,
            borderRadius: BorderRadius.circular(widget.embedded ? 0 : 20),
            border: widget.embedded
                ? null
                : Border.all(color: FxPalette.divider, width: 1),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isReorderMode)
                    Container(
                      height: 20,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Icon(
                            Icons.unfold_more_rounded,
                            size: 14,
                            color: Colors.white.withOpacity(0.68),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Reorder clips',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.18,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Drop to apply',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.44),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 20,
                      child: Row(
                        children: [
                          SizedBox(
                            width: _timeReadoutWidth,
                            child: Text(
                              '${_formatClock(_displayedCurrentSeconds)} / ${_formatWholeSeconds(widget.timelineDuration)}',
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: const TextStyle(
                                color: FxPalette.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _TimelineRulerPainter(
                                  scrollOffset: _scrollController.hasClients
                                      ? _scrollController.offset
                                      : 0,
                                  playheadLeft: math.max(
                                      0, _playheadLeft - _timeReadoutWidth - 6),
                                  viewportWidth: math.max(
                                    0,
                                    constraints.maxWidth -
                                        (_panelPadding * 2) -
                                        _timeReadoutWidth -
                                        6,
                                  ),
                                  secondsWidth: _secondsWidth,
                                  durationSeconds: widget.timelineDuration,
                                  fps: _timelineFps,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, scrollConstraints) {
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: _handleScrollNotification,
                                child: Listener(
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: _handlePointerDown,
                                  onPointerMove: _handlePointerMove,
                                  onPointerUp: _handlePointerEnd,
                                  onPointerCancel: _handlePointerEnd,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onScaleStart: _handleScaleStart,
                                    onScaleUpdate: _handleScaleUpdate,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SingleChildScrollView(
                                        controller: _scrollController,
                                        scrollDirection: Axis.horizontal,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        child: SizedBox(
                                          width: contentWidth,
                                          height: scrollConstraints.maxHeight,
                                          child: SingleChildScrollView(
                                            controller: _verticalController,
                                            physics:
                                                const BouncingScrollPhysics(),
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                minHeight:
                                                    scrollConstraints.maxHeight,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  for (var i = 0;
                                                      i < widget.tracks.length;
                                                      i++) ...[
                                                    _TimelineTrackRow(
                                                      leadingOffset:
                                                          _leadingOffset,
                                                      controlTileSize:
                                                          _controlTileSize,
                                                      controlGap: _controlGap,
                                                      splitGap: _splitGap,
                                                      rowHeight: _rowHeight,
                                                      secondsWidth:
                                                          _secondsWidth,
                                                      track: widget.tracks[i],
                                                      isPlaying:
                                                          widget.isPlaying,
                                                      selectedClipId:
                                                          widget.selectedClipId,
                                                      onClipSelected:
                                                          widget.onClipSelected,
                                                      onClipLongPressStart:
                                                          (clip) =>
                                                              _beginClipReorder(
                                                        i,
                                                        clip,
                                                      ),
                                                      onClipLongPressMove:
                                                          (clip, deltaDx) =>
                                                              _updateClipReorder(
                                                        i,
                                                        clip,
                                                        deltaDx,
                                                      ),
                                                      onClipLongPressEnd:
                                                          (clip) =>
                                                              _finishClipReorder(
                                                        i,
                                                        clip,
                                                      ),
                                                      onBackgroundTap: widget
                                                          .onBackgroundTap,
                                                      assetPathResolver: widget
                                                          .assetPathResolver,
                                                      assetThumbnailResolver: widget
                                                          .assetThumbnailResolver,
                                                    ),
                                                    if (i !=
                                                        widget.tracks.length -
                                                            1)
                                                      const SizedBox(
                                                        height: _rowGap,
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_isReorderMode)
                              Positioned.fill(
                                child: _buildReorderOverlay(
                                  viewportWidth: contentViewportWidth,
                                  viewportHeight: scrollConstraints.maxHeight,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (!_isReorderMode)
                Positioned(
                  left: _playheadLeft,
                  top: 30,
                  bottom: 10,
                  child: IgnorePointer(
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.22),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineTrackRow extends StatelessWidget {
  const _TimelineTrackRow({
    required this.leadingOffset,
    required this.controlTileSize,
    required this.controlGap,
    required this.splitGap,
    required this.rowHeight,
    required this.secondsWidth,
    required this.track,
    required this.isPlaying,
    required this.selectedClipId,
    required this.onClipSelected,
    required this.onClipLongPressStart,
    required this.onClipLongPressMove,
    required this.onClipLongPressEnd,
    required this.onBackgroundTap,
    required this.assetPathResolver,
    required this.assetThumbnailResolver,
  });

  final double leadingOffset;
  final double controlTileSize;
  final double controlGap;
  final double splitGap;
  final double rowHeight;
  final double secondsWidth;
  final TimelineTrackData track;
  final bool isPlaying;
  final String? selectedClipId;
  final ValueChanged<String> onClipSelected;
  final ValueChanged<TimelineClipData>? onClipLongPressStart;
  final void Function(TimelineClipData clip, double deltaDx)?
      onClipLongPressMove;
  final ValueChanged<TimelineClipData>? onClipLongPressEnd;
  final VoidCallback? onBackgroundTap;
  final TimelineAssetPathResolver? assetPathResolver;
  final TimelineAssetThumbnailResolver? assetThumbnailResolver;

  IconData get _trackIcon {
    switch (track.kind) {
      case TimelineTrackKind.video:
        return Icons.videocam_rounded;
      case TimelineTrackKind.image:
        return Icons.image_rounded;
      case TimelineTrackKind.audio:
        return Icons.music_note_rounded;
      case TimelineTrackKind.text:
        return Icons.text_fields_rounded;
      case TimelineTrackKind.lipSync:
        return Icons.graphic_eq_rounded;
    }
  }

  IconData get _clipIcon {
    switch (track.kind) {
      case TimelineTrackKind.video:
        return Icons.videocam_rounded;
      case TimelineTrackKind.image:
        return Icons.image_rounded;
      case TimelineTrackKind.audio:
        return Icons.music_note_rounded;
      case TimelineTrackKind.text:
        return Icons.text_fields_rounded;
      case TimelineTrackKind.lipSync:
        return Icons.graphic_eq_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clipChildren = <Widget>[];
    final splitBridges = <Widget>[];
    final splitCutMarkers = <Widget>[];
    const splitBridgeWidth = 18.0;
    const splitBridgeHeight = 16.0;
    const splitMarkerWidth = 2.0;
    final clipStart = leadingOffset + controlTileSize + controlGap;
    var cursor = clipStart;
    for (var i = 0; i < track.clips.length; i++) {
      final clip = track.clips[i];
      final isSelected = selectedClipId == clip.id;
      final assetPath =
          clip.assetId == null ? null : assetPathResolver?.call(clip.assetId!);
      final assetThumbnailBytes = clip.assetId == null
          ? null
          : assetThumbnailResolver?.call(clip.assetId!);
      final clipWidth = clip.timelineWidth(secondsWidth);

      clipChildren.add(
        Positioned(
          key: ValueKey<String>(clip.id),
          left: cursor,
          top: 2,
          child: clip.type == TimelineClipType.placeholder
              ? _TimelinePlaceholderClip(
                  width: clipWidth,
                  label: clip.label ?? track.placeholderLabel ?? 'Add',
                  isSelected: isSelected,
                  onTap: () => onClipSelected(clip.id),
                  onLongPressStart: onClipLongPressStart == null
                      ? null
                      : () => onClipLongPressStart!(clip),
                  onLongPressMoveUpdate: onClipLongPressMove == null
                      ? null
                      : (details) => onClipLongPressMove!(
                            clip,
                            details.offsetFromOrigin.dx,
                          ),
                  onLongPressEnd: onClipLongPressEnd == null
                      ? null
                      : () => onClipLongPressEnd!(clip),
                )
              : _TimelineMediaClip(
                  width: clipWidth,
                  tone: clip.tone,
                  icon: _clipIcon,
                  trackKind: track.kind,
                  isPlaying: isPlaying,
                  secondsWidth: secondsWidth,
                  assetPath: assetPath,
                  initialThumbnailBytes: assetThumbnailBytes,
                  sourceOffsetSeconds: clip.sourceOffsetSeconds ?? 0,
                  durationSeconds: clip.duration,
                  filmstripReferenceOffsetSeconds:
                      clip.filmstripReferenceOffsetSeconds ??
                          (clip.sourceOffsetSeconds ?? 0),
                  filmstripReferenceDurationSeconds:
                      clip.filmstripReferenceDurationSeconds ?? clip.duration,
                  isSelected: isSelected,
                  onTap: () => onClipSelected(clip.id),
                  onLongPressStart: onClipLongPressStart == null
                      ? null
                      : () => onClipLongPressStart!(clip),
                  onLongPressMoveUpdate: onClipLongPressMove == null
                      ? null
                      : (details) => onClipLongPressMove!(
                            clip,
                            details.offsetFromOrigin.dx,
                          ),
                  onLongPressEnd: onClipLongPressEnd == null
                      ? null
                      : () => onClipLongPressEnd!(clip),
                ),
        ),
      );

      if (i != track.clips.length - 1) {
        final next = track.clips[i + 1];
        final showBridge =
            clip.splitGroupId != null && clip.splitGroupId == next.splitGroupId;

        if (showBridge) {
          final cutCenterX = cursor + clipWidth + (splitGap / 2);
          splitCutMarkers.add(
            Positioned(
              left: cutCenterX - (splitMarkerWidth / 2),
              top: 3,
              bottom: 3,
              child: IgnorePointer(
                child: Container(
                  width: splitMarkerWidth,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.42),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.08),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          splitBridges.add(
            Positioned(
              left: cutCenterX - (splitBridgeWidth / 2),
              top: (rowHeight - splitBridgeHeight) / 2,
              child: const IgnorePointer(
                child: _TransitionBridge(),
              ),
            ),
          );
          cursor += clipWidth + splitGap;
        } else {
          cursor += clipWidth + controlGap;
        }
      } else {
        cursor += clipWidth;
      }
    }

    final rowWidth = math.max(
      cursor + controlGap,
      clipStart + 12,
    );

    return SizedBox(
      width: rowWidth,
      height: rowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBackgroundTap,
            ),
          ),
          Positioned(
            left: leadingOffset,
            top: 1,
            child: Container(
              width: controlTileSize,
              height: controlTileSize,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                  width: 1,
                ),
              ),
              child: Icon(
                _trackIcon,
                size: 18,
                color: FxPalette.textMuted,
              ),
            ),
          ),
          ...clipChildren,
          ...splitCutMarkers,
          ...splitBridges,
        ],
      ),
    );
  }
}

class _TimelineReorderRowLayout {
  const _TimelineReorderRowLayout({
    required this.stationaryClips,
    required this.slotCenters,
    required this.leftByClipId,
    required this.widthByClipId,
    required this.rowWidth,
  });

  final List<TimelineClipData> stationaryClips;
  final List<double> slotCenters;
  final Map<String, double> leftByClipId;
  final Map<String, double> widthByClipId;
  final double rowWidth;
}

class _TimelineReorderTrackRow extends StatelessWidget {
  const _TimelineReorderTrackRow({
    required this.leadingOffset,
    required this.controlTileSize,
    required this.controlGap,
    required this.rowHeight,
    required this.cardHeight,
    required this.track,
    required this.selectedClipId,
    required this.draggedClipId,
    required this.hoverInsertionIndex,
    required this.layout,
    required this.draggedCenter,
    required this.draggedWidth,
    required this.isDropSettling,
    required this.assetPathResolver,
    required this.assetThumbnailResolver,
  });

  final double leadingOffset;
  final double controlTileSize;
  final double controlGap;
  final double rowHeight;
  final double cardHeight;
  final TimelineTrackData track;
  final String? selectedClipId;
  final String? draggedClipId;
  final int? hoverInsertionIndex;
  final _TimelineReorderRowLayout layout;
  final double? draggedCenter;
  final double? draggedWidth;
  final bool isDropSettling;
  final TimelineAssetPathResolver? assetPathResolver;
  final TimelineAssetThumbnailResolver? assetThumbnailResolver;

  IconData get _trackIcon {
    switch (track.kind) {
      case TimelineTrackKind.video:
        return Icons.videocam_rounded;
      case TimelineTrackKind.image:
        return Icons.image_rounded;
      case TimelineTrackKind.audio:
        return Icons.music_note_rounded;
      case TimelineTrackKind.text:
        return Icons.text_fields_rounded;
      case TimelineTrackKind.lipSync:
        return Icons.graphic_eq_rounded;
    }
  }

  IconData get _clipIcon {
    switch (track.kind) {
      case TimelineTrackKind.video:
        return Icons.videocam_rounded;
      case TimelineTrackKind.image:
        return Icons.image_rounded;
      case TimelineTrackKind.audio:
        return Icons.music_note_rounded;
      case TimelineTrackKind.text:
        return Icons.text_fields_rounded;
      case TimelineTrackKind.lipSync:
        return Icons.graphic_eq_rounded;
    }
  }

  Widget _buildClipCard(TimelineClipData clip, double width,
      {bool isDragged = false}) {
    final isSelected = selectedClipId == clip.id;
    final assetPath =
        clip.assetId == null ? null : assetPathResolver?.call(clip.assetId!);
    final assetThumbnailBytes = clip.assetId == null
        ? null
        : assetThumbnailResolver?.call(clip.assetId!);

    if (clip.type == TimelineClipType.placeholder) {
      return _TimelinePlaceholderClip(
        width: width,
        height: cardHeight,
        label: clip.label ?? track.placeholderLabel ?? 'Add',
        isSelected: isSelected,
        isDragged: isDragged,
        onTap: () {},
      );
    }

    return _TimelineMediaClip(
      width: width,
      height: cardHeight,
      tone: clip.tone,
      icon: _clipIcon,
      trackKind: track.kind,
      isPlaying: false,
      secondsWidth: clip.duration <= 0 ? 1 : width / clip.duration,
      assetPath: assetPath,
      initialThumbnailBytes: assetThumbnailBytes,
      sourceOffsetSeconds: clip.sourceOffsetSeconds ?? 0,
      durationSeconds: clip.duration,
      filmstripReferenceOffsetSeconds:
          clip.filmstripReferenceOffsetSeconds ?? (clip.sourceOffsetSeconds ?? 0),
      filmstripReferenceDurationSeconds:
          clip.filmstripReferenceDurationSeconds ?? clip.duration,
      isSelected: isSelected,
      isDragged: isDragged,
      onTap: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    TimelineClipData? draggedClip;
    final draggedClipId = this.draggedClipId;
    if (draggedClipId != null) {
      for (final clip in track.clips) {
        if (clip.id == draggedClipId) {
          draggedClip = clip;
          break;
        }
      }
    }
    final resolvedDraggedWidth = draggedWidth ??
        (draggedClip == null ? null : layout.widthByClipId[draggedClip.id]);
    final draggedLeft = draggedClip == null ||
            draggedCenter == null ||
            resolvedDraggedWidth == null
        ? null
        : draggedCenter! - (resolvedDraggedWidth / 2);

    return SizedBox(
      width: layout.rowWidth,
      height: rowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: leadingOffset,
            top: 1,
            child: Container(
              width: controlTileSize,
              height: controlTileSize,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withOpacity(0.07),
                  width: 1,
                ),
              ),
              child: Icon(
                _trackIcon,
                size: 18,
                color: Colors.white.withOpacity(0.78),
              ),
            ),
          ),
          if (draggedClipId != null)
            for (var slotIndex = 0;
                slotIndex < layout.slotCenters.length;
                slotIndex++)
              Positioned(
                left: layout.slotCenters[slotIndex] -
                    ((slotIndex == hoverInsertionIndex) ? 17 : 6),
                top: 8,
                child: _TimelineInsertionSlot(
                  isActive: slotIndex == hoverInsertionIndex,
                ),
              ),
          for (final clip in layout.stationaryClips)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              left: layout.leftByClipId[clip.id]!,
              top: 1,
              child: _buildClipCard(
                clip,
                layout.widthByClipId[clip.id]!,
              ),
            ),
          if (draggedClip != null &&
              draggedLeft != null &&
              resolvedDraggedWidth != null)
            (isDropSettling
                ? AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    left: draggedLeft,
                    top: 0,
                    child: _buildClipCard(
                      draggedClip,
                      resolvedDraggedWidth,
                      isDragged: true,
                    ),
                  )
                : Positioned(
                    left: draggedLeft,
                    top: 0,
                    child: Transform.scale(
                      scale: 1.03,
                      child: _buildClipCard(
                        draggedClip,
                        resolvedDraggedWidth,
                        isDragged: true,
                      ),
                    ),
                  )),
        ],
      ),
    );
  }
}

class _TimelineMediaClip extends StatelessWidget {
  const _TimelineMediaClip({
    required this.width,
    required this.tone,
    required this.icon,
    required this.trackKind,
    required this.isPlaying,
    required this.secondsWidth,
    required this.assetPath,
    required this.initialThumbnailBytes,
    required this.sourceOffsetSeconds,
    required this.durationSeconds,
    required this.filmstripReferenceOffsetSeconds,
    required this.filmstripReferenceDurationSeconds,
    required this.isSelected,
    required this.onTap,
    this.height = 34,
    this.isDragged = false,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  final double width;
  final TimelineClipTone tone;
  final IconData icon;
  final TimelineTrackKind trackKind;
  final bool isPlaying;
  final double secondsWidth;
  final String? assetPath;
  final Uint8List? initialThumbnailBytes;
  final double sourceOffsetSeconds;
  final double durationSeconds;
  final double filmstripReferenceOffsetSeconds;
  final double filmstripReferenceDurationSeconds;
  final bool isSelected;
  final VoidCallback onTap;
  final double height;
  final bool isDragged;
  final VoidCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final VoidCallback? onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final accent = switch (tone) {
      TimelineClipTone.hero => const Color(0xFF7BFF43),
      TimelineClipTone.heroMuted => const Color(0xFF71E84B),
      TimelineClipTone.placeholder => FxPalette.clipFill,
    };
    final hasVideoFrames =
        trackKind == TimelineTrackKind.video && assetPath != null;
    final hasImagePreview =
        trackKind == TimelineTrackKind.image && assetPath != null;
    final baseColor =
        hasVideoFrames || hasImagePreview ? const Color(0xFF252525) : accent;

    return GestureDetector(
      onTap: onTap,
      onLongPressStart:
          onLongPressStart == null ? null : (_) => onLongPressStart!(),
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressEnd: onLongPressEnd == null ? null : (_) => onLongPressEnd!(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.28)
                : Colors.white.withOpacity(0.06),
            width: isSelected ? 1.2 : 0.9,
          ),
          boxShadow: [
            if (isSelected || isDragged)
              BoxShadow(
                color: Colors.black.withOpacity(isDragged ? 0.32 : 0.22),
                blurRadius: isDragged ? 16 : 8,
                offset: Offset(0, isDragged ? 8 : 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasVideoFrames)
                _TimelineVideoFilmstrip(
                  path: assetPath!,
                  isPlaying: isPlaying,
                  seedThumbnailBytes: initialThumbnailBytes,
                  width: width,
                  height: height,
                  secondsWidth: secondsWidth,
                  sourceOffsetSeconds: sourceOffsetSeconds,
                  durationSeconds: durationSeconds,
                  filmstripReferenceOffsetSeconds:
                      filmstripReferenceOffsetSeconds,
                  filmstripReferenceDurationSeconds:
                      filmstripReferenceDurationSeconds,
                )
              else if (hasImagePreview)
                _TimelineImageFill(path: assetPath!)
              else
                ColoredBox(color: accent),
              if (!hasVideoFrames && !hasImagePreview)
                Row(
                  children: List.generate(
                    math.max(2, width ~/ 74),
                    (index) => Expanded(
                      child: Center(
                        child: Icon(
                          icon,
                          size: 18,
                          color: Colors.black.withOpacity(0.85),
                        ),
                      ),
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.07),
                      Colors.transparent,
                      Colors.black.withOpacity(0.06),
                    ],
                  ),
                ),
              ),
              if (isSelected)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: _TimelineSelectionPulseBorder(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineImageFill extends StatelessWidget {
  const _TimelineImageFill({
    required this.path,
  });

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(color: FxPalette.clipFillAlt);
      },
    );
  }
}

class _TimelineSelectionPulseBorder extends StatefulWidget {
  const _TimelineSelectionPulseBorder();

  @override
  State<_TimelineSelectionPulseBorder> createState() =>
      _TimelineSelectionPulseBorderState();
}

class _TimelineSelectionPulseBorderState
    extends State<_TimelineSelectionPulseBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final borderOpacity = lerpDouble(0.58, 0.98, t)!;
        final borderWidth = lerpDouble(1.35, 2.2, t)!;
        final glowOpacity = lerpDouble(0.03, 0.14, t)!;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: Colors.white.withOpacity(borderOpacity),
              width: borderWidth,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(glowOpacity),
                blurRadius: lerpDouble(5, 12, t)!,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineVideoFilmstrip extends StatefulWidget {
  const _TimelineVideoFilmstrip({
    required this.path,
    required this.isPlaying,
    required this.seedThumbnailBytes,
    required this.width,
    required this.height,
    required this.secondsWidth,
    required this.sourceOffsetSeconds,
    required this.durationSeconds,
    required this.filmstripReferenceOffsetSeconds,
    required this.filmstripReferenceDurationSeconds,
  });

  final String path;
  final bool isPlaying;
  final Uint8List? seedThumbnailBytes;
  final double width;
  final double height;
  final double secondsWidth;
  final double sourceOffsetSeconds;
  final double durationSeconds;
  final double filmstripReferenceOffsetSeconds;
  final double filmstripReferenceDurationSeconds;

  @override
  State<_TimelineVideoFilmstrip> createState() =>
      _TimelineVideoFilmstripState();
}

class _TimelineVideoFilmstripState extends State<_TimelineVideoFilmstrip> {
  static const Duration _thumbnailLoadDelay = Duration.zero;

  Future<List<Uint8List>>? _thumbnailsFuture;
  List<Uint8List>? _seedThumbnails;
  List<Uint8List>? _referenceThumbnails;

  int get _tileCount => math.max(2, (widget.width / 54).ceil());

  int get _targetWidth {
    final tileWidth = widget.width / _tileCount;
    return math.max(96, (tileWidth * 2).round());
  }

  int get _targetHeight => math.max(68, (widget.height * 2).round());

  bool get _usesReferenceStrip =>
      (widget.filmstripReferenceOffsetSeconds - widget.sourceOffsetSeconds)
              .abs() >
          0.001 ||
      (widget.filmstripReferenceDurationSeconds - widget.durationSeconds).abs() >
          0.001;

  double get _referenceWidth => math.max(
        widget.width,
        widget.filmstripReferenceDurationSeconds * widget.secondsWidth,
      );

  int get _referenceTileCount => math.max(2, (_referenceWidth / 54).ceil());

  int get _referenceTargetWidth {
    final tileWidth = _referenceWidth / _referenceTileCount;
    return math.max(96, (tileWidth * 2).round());
  }

  @override
  void initState() {
    super.initState();
    _refreshThumbnails();
  }

  @override
  void didUpdateWidget(covariant _TimelineVideoFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.seedThumbnailBytes != widget.seedThumbnailBytes ||
        (oldWidget.width - widget.width).abs() > 0.5 ||
        (oldWidget.height - widget.height).abs() > 0.5 ||
        (oldWidget.secondsWidth - widget.secondsWidth).abs() > 0.001 ||
        (oldWidget.sourceOffsetSeconds - widget.sourceOffsetSeconds).abs() >
            0.001 ||
        (oldWidget.durationSeconds - widget.durationSeconds).abs() > 0.001 ||
        (oldWidget.filmstripReferenceOffsetSeconds -
                    widget.filmstripReferenceOffsetSeconds)
                .abs() >
            0.001 ||
        (oldWidget.filmstripReferenceDurationSeconds -
                    widget.filmstripReferenceDurationSeconds)
                .abs() >
            0.001) {
      _refreshThumbnails();
    }
  }

  void _refreshThumbnails() {
    final timestamps = _buildTimestamps(
      startSeconds: widget.sourceOffsetSeconds,
      durationSeconds: widget.durationSeconds,
      tileCount: _tileCount,
    );
    final referenceTimestamps = _buildTimestamps(
      startSeconds: widget.filmstripReferenceOffsetSeconds,
      durationSeconds: widget.filmstripReferenceDurationSeconds,
      tileCount: _referenceTileCount,
    );
    final resolvedSegmentThumbnails = _TimelineFilmstripCache.peek(
      path: widget.path,
      sourceOffsetSeconds: widget.sourceOffsetSeconds,
      durationSeconds: widget.durationSeconds,
      tileCount: _tileCount,
      targetWidth: _targetWidth,
      targetHeight: _targetHeight,
    );
    final resolvedReferenceThumbnails = _usesReferenceStrip
        ? _TimelineFilmstripCache.peek(
            path: widget.path,
            sourceOffsetSeconds: widget.filmstripReferenceOffsetSeconds,
            durationSeconds: widget.filmstripReferenceDurationSeconds,
            tileCount: _referenceTileCount,
            targetWidth: _referenceTargetWidth,
            targetHeight: _targetHeight,
          )
        : null;
    _referenceThumbnails =
        resolvedReferenceThumbnails != null &&
                resolvedReferenceThumbnails.length >= _referenceTileCount
            ? resolvedReferenceThumbnails
            : null;
    _seedThumbnails = resolvedSegmentThumbnails;
    _seedThumbnails ??= _TimelineFilmstripCache.peekFrames(
      path: widget.path,
      targetWidth: _targetWidth,
      targetHeight: _targetHeight,
      timestampsSeconds: timestamps,
    );
    _seedThumbnails ??= _TimelineFilmstripCache.peekFrames(
      path: widget.path,
      targetWidth: _referenceTargetWidth,
      targetHeight: _targetHeight,
      timestampsSeconds: referenceTimestamps,
    );
    _seedThumbnails ??= _seedPosterFrames();

    if (_referenceThumbnails != null) {
      _thumbnailsFuture = null;
      return;
    }

    if (resolvedSegmentThumbnails != null &&
        resolvedSegmentThumbnails.length >= _tileCount) {
      _thumbnailsFuture = null;
      return;
    }
    _thumbnailsFuture = Future<List<Uint8List>>.delayed(
      _thumbnailLoadDelay,
      () => _usesReferenceStrip
          ? _TimelineFilmstripCache.load(
              path: widget.path,
              sourceOffsetSeconds: widget.filmstripReferenceOffsetSeconds,
              durationSeconds: widget.filmstripReferenceDurationSeconds,
              tileCount: _referenceTileCount,
              targetWidth: _referenceTargetWidth,
              targetHeight: _targetHeight,
              timestampsSeconds: referenceTimestamps,
            )
          : _TimelineFilmstripCache.load(
              path: widget.path,
              sourceOffsetSeconds: widget.sourceOffsetSeconds,
              durationSeconds: widget.durationSeconds,
              tileCount: _tileCount,
              targetWidth: _targetWidth,
              targetHeight: _targetHeight,
              timestampsSeconds: timestamps,
            ),
    );
  }

  List<double> _buildTimestamps({
    required double startSeconds,
    required double durationSeconds,
    required int tileCount,
  }) {
    return List<double>.generate(tileCount, (index) {
      final fraction = (index + 0.5) / tileCount;
      return startSeconds + (durationSeconds * fraction);
    });
  }

  List<Uint8List>? _seedPosterFrames() {
    final seed = widget.seedThumbnailBytes;
    if (seed == null || seed.isEmpty) {
      return null;
    }
    return List<Uint8List>.unmodifiable(
      List<Uint8List>.filled(_tileCount, seed),
    );
  }

  Widget _buildFallback() {
    return ColoredBox(
      color: const Color(0xFF2B2B2B),
      child: Row(
        children: List.generate(
          _tileCount,
          (index) => Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.03),
                    Colors.transparent,
                    Colors.black.withOpacity(0.08),
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStrip({
    required List<Uint8List> thumbnails,
    required int tileCount,
    required double width,
  }) {
    final tileWidth = width / tileCount;
    return SizedBox(
      width: width,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var index = 0; index < tileCount; index++)
            Positioned(
              left: tileWidth * index,
              top: 0,
              bottom: 0,
              width: index == tileCount - 1 ? tileWidth : tileWidth + 1.5,
              child: Image.memory(
                thumbnails[index % thumbnails.length],
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentThumbnails(List<Uint8List> thumbnails) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildStrip(
          thumbnails: thumbnails,
          tileCount: _tileCount,
          width: constraints.maxWidth,
        );
      },
    );
  }

  Widget _buildReferenceThumbnails(List<Uint8List> thumbnails) {
    final referenceDuration =
        math.max(widget.filmstripReferenceDurationSeconds, 0.001);
    final relativeStart = ((widget.sourceOffsetSeconds -
                widget.filmstripReferenceOffsetSeconds) /
            referenceDuration)
        .clamp(0.0, 1.0);
    final relativeWidth =
        (widget.durationSeconds / referenceDuration).clamp(0.0001, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullStripWidth =
            math.max(constraints.maxWidth, constraints.maxWidth / relativeWidth);
        final left = -(relativeStart * fullStripWidth);
        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: fullStripWidth,
                child: _buildStrip(
                  thumbnails: thumbnails,
                  tileCount: _referenceTileCount,
                  width: fullStripWidth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Uint8List>>(
      future: _thumbnailsFuture,
      builder: (context, snapshot) {
        final thumbnails = snapshot.data;
        if (_usesReferenceStrip) {
          final referenceThumbnails = _referenceThumbnails ??
              ((thumbnails != null && thumbnails.isNotEmpty) ? thumbnails : null);
          if (referenceThumbnails != null && referenceThumbnails.isNotEmpty) {
            return _buildReferenceThumbnails(referenceThumbnails);
          }
        }

        final seededThumbnails = _seedThumbnails;
        if (seededThumbnails != null && seededThumbnails.isNotEmpty) {
          return _buildSegmentThumbnails(seededThumbnails);
        }

        if (thumbnails != null && thumbnails.isNotEmpty) {
          return _buildSegmentThumbnails(thumbnails);
        }

        if (snapshot.hasError) {
          return _buildFallback();
        }

        return _buildFallback();
      },
    );
  }
}

class _TimelineFilmstripCache {
  static final Map<String, Future<List<Uint8List>>> _entries =
      <String, Future<List<Uint8List>>>{};
  static final Map<String, List<Uint8List>> _segmentEntries =
      <String, List<Uint8List>>{};
  static final Map<String, Uint8List> _frameEntries = <String, Uint8List>{};

  static List<Uint8List>? peek({
    required String path,
    required double sourceOffsetSeconds,
    required double durationSeconds,
    required int tileCount,
    required int targetWidth,
    required int targetHeight,
  }) {
    final key = _segmentKey(
      path: path,
      sourceOffsetSeconds: sourceOffsetSeconds,
      durationSeconds: durationSeconds,
      tileCount: tileCount,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    return _segmentEntries[key];
  }

  static List<Uint8List>? peekFrames({
    required String path,
    required List<double> timestampsSeconds,
    required int targetWidth,
    required int targetHeight,
  }) {
    final normalizedTimestamps =
        timestampsSeconds.map(_normalizeTimestamp).toList(growable: false);
    final thumbnails = <Uint8List>[
      for (final timestamp in normalizedTimestamps)
        if (_frameEntries[_frameKey(
          path: path,
          timestampSeconds: timestamp,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        )] case final bytes?)
          bytes,
    ];
    if (thumbnails.isEmpty) {
      return null;
    }
    return List<Uint8List>.unmodifiable(thumbnails);
  }

  static double _normalizeTimestamp(double value) {
    return (value * 4).round() / 4;
  }

  static String _frameKey({
    required String path,
    required double timestampSeconds,
    required int targetWidth,
    required int targetHeight,
  }) {
    return [
      path,
      timestampSeconds.toStringAsFixed(2),
      targetWidth,
      targetHeight,
    ].join('|');
  }

  static String _segmentKey({
    required String path,
    required double sourceOffsetSeconds,
    required double durationSeconds,
    required int tileCount,
    required int targetWidth,
    required int targetHeight,
  }) {
    return [
      path,
      sourceOffsetSeconds.toStringAsFixed(3),
      durationSeconds.toStringAsFixed(3),
      tileCount,
      targetWidth,
      targetHeight,
    ].join('|');
  }

  static Future<List<Uint8List>> load({
    required String path,
    required double sourceOffsetSeconds,
    required double durationSeconds,
    required int tileCount,
    required int targetWidth,
    required int targetHeight,
    required List<double> timestampsSeconds,
  }) {
    final normalizedTimestamps =
        timestampsSeconds.map(_normalizeTimestamp).toList(growable: false);
    final frameKeys = normalizedTimestamps
        .map(
          (timestamp) => _frameKey(
            path: path,
            timestampSeconds: timestamp,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
          ),
        )
        .toList(growable: false);
    final missingTimestamps = <double>[];
    final missingFrameKeys = <String>[];
    for (var i = 0; i < frameKeys.length; i++) {
      final key = frameKeys[i];
      if (_frameEntries.containsKey(key)) {
        continue;
      }
      if (missingFrameKeys.contains(key)) {
        continue;
      }
      missingFrameKeys.add(key);
      missingTimestamps.add(normalizedTimestamps[i]);
    }

    final segmentKey = _segmentKey(
      path: path,
      sourceOffsetSeconds: sourceOffsetSeconds,
      durationSeconds: durationSeconds,
      tileCount: tileCount,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final key = [
      segmentKey,
      for (final timestamp in normalizedTimestamps)
        timestamp.toStringAsFixed(2),
    ].join('|');
    return _entries.putIfAbsent(
      key,
      () async {
        try {
          if (missingTimestamps.isNotEmpty) {
            final generated =
                await NativeMediaThumbnailer.generateVideoThumbnails(
              path: path,
              timestampsSeconds: missingTimestamps,
              targetWidth: targetWidth,
              targetHeight: targetHeight,
            );
            final resolvedCount =
                math.min(generated.length, missingFrameKeys.length);
            for (var i = 0; i < resolvedCount; i++) {
              _frameEntries[missingFrameKeys[i]] = generated[i];
            }
          }
          final thumbnails = <Uint8List>[
            for (final frameKey in frameKeys)
              if (_frameEntries[frameKey] case final bytes?) bytes,
          ];
          if (thumbnails.isNotEmpty) {
            _segmentEntries[segmentKey] =
                List<Uint8List>.unmodifiable(thumbnails);
          } else {
            _entries.remove(key);
          }
          return thumbnails;
        } catch (_) {
          _entries.remove(key);
          rethrow;
        }
      },
    );
  }
}

class _TimelinePlaceholderClip extends StatelessWidget {
  const _TimelinePlaceholderClip({
    required this.width,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.height = 34,
    this.isDragged = false,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  final double width;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double height;
  final bool isDragged;
  final VoidCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final VoidCallback? onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final isCompact = width < 126;
    final hideLabel = width < 108;

    return GestureDetector(
      onTap: onTap,
      onLongPressStart:
          onLongPressStart == null ? null : (_) => onLongPressStart!(),
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressEnd: onLongPressEnd == null ? null : (_) => onLongPressEnd!(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.24)
                : Colors.white.withOpacity(0.04),
            width: isSelected ? 1.15 : 0.95,
          ),
          boxShadow: [
            if (isDragged)
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12),
        child: Row(
          children: [
            const Icon(
              Icons.add_rounded,
              size: 18,
              color: FxPalette.textMuted,
            ),
            if (!hideLabel) ...[
              SizedBox(width: isCompact ? 4 : 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FxPalette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimelineInsertionSlot extends StatelessWidget {
  const _TimelineInsertionSlot({
    required this.isActive,
  });

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      width: isActive ? 34 : 12,
      height: 22,
      decoration: BoxDecoration(
        color: isActive
            ? Colors.white.withOpacity(0.16)
            : Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive
              ? Colors.white.withOpacity(0.34)
              : Colors.white.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: Colors.white.withOpacity(0.08),
              blurRadius: 8,
            ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 2,
        height: isActive ? 12 : 8,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(isActive ? 0.82 : 0.3),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _TransitionBridge extends StatelessWidget {
  const _TransitionBridge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withOpacity(0.34),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.06),
              blurRadius: 5,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  const _TimelineRulerPainter({
    required this.scrollOffset,
    required this.playheadLeft,
    required this.viewportWidth,
    required this.secondsWidth,
    required this.durationSeconds,
    required this.fps,
  });

  final double scrollOffset;
  final double playheadLeft;
  final double viewportWidth;
  final double secondsWidth;
  final double durationSeconds;
  final double fps;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1;
    final majorTickPaint = Paint()
      ..color = Colors.white.withOpacity(0.34)
      ..strokeWidth = 1.1;

    final textStyle = TextStyle(
      color: Colors.white.withOpacity(0.62),
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );

    final minorStep = _pickStep(14);
    final majorStep = _pickStep(34);
    final labelStep = _pickStep(68);
    final visibleStart =
        math.max(0, (scrollOffset - playheadLeft - 24) / secondsWidth);
    final visibleEnd = math.min(
        durationSeconds, (scrollOffset + viewportWidth) / secondsWidth);
    final firstTick = (visibleStart / minorStep).floor() * minorStep;
    var lastLabelRight = -1000.0;

    for (double time = firstTick;
        time <= visibleEnd + minorStep;
        time += minorStep) {
      final x = playheadLeft + time * secondsWidth - scrollOffset;
      if (x < 0 || x > size.width) {
        continue;
      }

      final isMajor = _isMultipleOf(time, majorStep);
      final tickHeight = isMajor ? 11.0 : 6.0;
      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        isMajor ? majorTickPaint : tickPaint,
      );

      if (_isMultipleOf(time, labelStep)) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: _formatLabel(time, labelStep),
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = (x + 4)
            .clamp(0.0, math.max(0.0, size.width - textPainter.width))
            .toDouble();
        if (labelX <= lastLabelRight + 8) {
          continue;
        }
        textPainter.paint(canvas, Offset(labelX, 0));
        lastLabelRight = labelX + textPainter.width;
      }
    }
  }

  double _pickStep(double minPixels) {
    final candidates = <double>[
      1 / fps,
      2 / fps,
      5 / fps,
      10 / fps,
      0.5,
      1,
      2,
      5,
      10,
      15,
      30,
      60,
    ];
    for (final step in candidates) {
      if (step * secondsWidth >= minPixels) {
        return step;
      }
    }
    return candidates.last;
  }

  bool _isMultipleOf(double value, double step) {
    if (step <= 0) {
      return false;
    }
    final ratio = value / step;
    return (ratio - ratio.round()).abs() < 0.001;
  }

  String _formatLabel(double seconds, double labelStep) {
    final totalFrames = (seconds * fps).round();
    final fpsInt = fps.round();
    final wholeSeconds = totalFrames ~/ fpsInt;
    final mins = wholeSeconds ~/ 60;
    final secs = wholeSeconds % 60;
    if (labelStep >= 1) {
      return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    final frames = totalFrames % fpsInt;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${frames.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.playheadLeft != playheadLeft ||
        oldDelegate.viewportWidth != viewportWidth ||
        oldDelegate.secondsWidth != secondsWidth ||
        oldDelegate.durationSeconds != durationSeconds ||
        oldDelegate.fps != fps;
  }
}
