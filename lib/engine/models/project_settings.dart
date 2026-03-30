class ProjectSettings {
  const ProjectSettings({
    required this.width,
    required this.height,
    required this.framesPerSecond,
    this.sampleRate = 48000,
  });

  final int width;
  final int height;
  final double framesPerSecond;
  final int sampleRate;

  Map<String, Object> toMap() {
    return <String, Object>{
      'width': width,
      'height': height,
      'fps': framesPerSecond,
      'sampleRate': sampleRate,
    };
  }
}
