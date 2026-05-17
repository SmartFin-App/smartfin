import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_fin/firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/di/injection_container.dart' as di;
import 'package:smart_fin/core/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SmartFinApp());
}

class SmartFinApp extends StatelessWidget {
  const SmartFinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SmartFin',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.cream,
        primaryColor: AppColors.primary,
        fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          surface: AppColors.white,
          onSurface: AppColors.textDark,
        ),
      ),
    );
  }
}
