import 'package:flutter/material.dart';

import '../../../editor/presentation/screens/fusionx_clean_ui_screen.dart';
import '../../../engine/presentation/screens/native_single_clip_playback_foundation_screen.dart';

class FusionXWorkspaceScreen extends StatefulWidget {
  const FusionXWorkspaceScreen({super.key});

  @override
  State<FusionXWorkspaceScreen> createState() => _FusionXWorkspaceScreenState();
}

class _FusionXWorkspaceScreenState extends State<FusionXWorkspaceScreen> {
  int _index = 1;

  final List<Widget> _screens = const <Widget>[
    FusionXCleanUiScreen(),
    NativeSingleClipPlaybackFoundationScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          setState(() {
            _index = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Shell',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_rounded),
            label: 'Engine V1',
          ),
        ],
      ),
    );
  }
}
