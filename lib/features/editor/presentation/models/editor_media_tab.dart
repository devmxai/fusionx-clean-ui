import 'package:flutter/material.dart';

enum EditorMediaTab {
  video('Video', Icons.videocam_rounded),
  image('Image', Icons.image_rounded),
  audio('Audio', Icons.music_note_rounded),
  text('Text', Icons.text_fields_rounded),
  lipSync('Lip Sync', Icons.graphic_eq_rounded);

  const EditorMediaTab(this.label, this.icon);

  final String label;
  final IconData icon;
}
