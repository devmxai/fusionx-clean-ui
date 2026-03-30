class EngineTime {
  const EngineTime(this.ticks);

  static const int ticksPerSecond = 48000;

  final int ticks;

  double get inSeconds => ticks / ticksPerSecond;

  int get inMicroseconds => (ticks * 1000000) ~/ ticksPerSecond;

  int get inMilliseconds => (ticks * 1000) ~/ ticksPerSecond;

  Map<String, Object> toMap() {
    return <String, Object>{
      'ticks': ticks,
    };
  }

  static EngineTime fromMap(Map<Object?, Object?> map) {
    return EngineTime((map['ticks'] as num?)?.round() ?? 0);
  }

  static EngineTime fromSeconds(double seconds) {
    return EngineTime((seconds * ticksPerSecond).round());
  }

  static EngineTime fromMilliseconds(int milliseconds) {
    return EngineTime((milliseconds * ticksPerSecond) ~/ 1000);
  }

  static EngineTime fromMicroseconds(int microseconds) {
    return EngineTime((microseconds * ticksPerSecond) ~/ 1000000);
  }

  @override
  String toString() => 'EngineTime(ticks: $ticks)';
}
