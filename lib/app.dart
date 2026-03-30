import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/editor/presentation/screens/fusionx_clean_ui_screen.dart';

class FusionXCleanUiApp extends StatelessWidget {
  const FusionXCleanUiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FusionX Clean UI',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildFxTheme(),
      darkTheme: buildFxTheme(),
      home: const FusionXCleanUiScreen(),
    );
  }
}
