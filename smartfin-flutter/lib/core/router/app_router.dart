import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_fin/core/di/injection_container.dart';
import 'package:smart_fin/features/transactions/presentation/transaction_list_screen.dart';
import 'package:smart_fin/features/scanner/presentation/camera_screen.dart';
import 'package:smart_fin/features/scanner/presentation/processing_screen.dart';
import 'package:smart_fin/features/scanner/presentation/verify_screen.dart';
import 'package:smart_fin/features/coach/presentation/coach_screen.dart';
import 'package:smart_fin/features/dashboard/presentation/dashboard_screen.dart';
import 'package:smart_fin/features/dashboard/presentation/profile_screen.dart';
import 'package:smart_fin/features/dashboard/presentation/account_settings_screen.dart';
import 'package:smart_fin/features/dashboard/presentation/security_privacy_screen.dart';
import 'package:smart_fin/features/auth/presentation/login_screen.dart';
import 'package:smart_fin/features/auth/presentation/signup_screen.dart';
import 'package:smart_fin/features/auth/presentation/initial_setup_screen.dart';
import 'package:smart_fin/features/splash/presentation/views/splash_view.dart';
import 'package:smart_fin/features/transactions/presentation/manual_add_screen.dart';
import 'package:smart_fin/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:smart_fin/features/subscriptions/presentation/subscriptions_screen.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';

// ---------------------------------------------------------------------------
// Protected routes — redirect to /login when not authenticated
// ---------------------------------------------------------------------------

const _protectedPaths = ['/home', '/history', '/coach', '/profile'];

String? _authRedirect(BuildContext context, GoRouterState state) {
  // BYPASS AUTH REDIRECT FOR TESTING
  return null;
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: _authRedirect,
  routes: [
    // ── Auth ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const SplashView(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      name: 'signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: '/setup',
      name: 'setup',
      builder: (context, state) => const InitialSetupScreen(),
    ),

    // ── Floating bottom nav routes ──────────────────────────────────────────────
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/history',
      name: 'history',
      // Optional query filters let another screen open History pre-filtered,
      // e.g. /history?type=expense&category=Food&month=2026-09 from the
      // dashboard's top-categories card. The bottom nav opens it unfiltered.
      builder: (context, state) => TransactionListScreen(
        initialType: state.uri.queryParameters['type'],
        initialCategory: state.uri.queryParameters['category'],
        initialMonth: state.uri.queryParameters['month'],
      ),
    ),
    GoRoute(
      path: '/coach',
      name: 'coach',
      builder: (context, state) => const CoachScreen(),
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/account-settings',
      name: 'account-settings',
      builder: (context, state) => const AccountSettingsScreen(),
    ),
    GoRoute(
      path: '/security-privacy',
      name: 'security-privacy',
      builder: (context, state) => const SecurityPrivacyScreen(),
    ),

    // ── Scanner flow ─────────────────────────────────────────────────────
    GoRoute(
      path: '/scanner',
      name: 'scanner',
      builder: (context, state) => const CameraScreen(),
    ),
    GoRoute(
      path: '/processing',
      name: 'processing',
      builder: (context, state) {
        // Gallery-watcher slips pass {'file': File, 'assetId': String} so the asset
        // can be marked processed only once its transaction is actually saved;
        // the camera passes a bare File.
        final extra = state.extra;
        if (extra is Map) {
          return ProcessingScreen(
            imageFile: extra['file'] as File?,
            slipAssetId: extra['assetId'] as String?,
          );
        }
        return ProcessingScreen(imageFile: extra as File?);
      },
    ),
    GoRoute(
      path: '/verify',
      name: 'verify',
      builder: (context, state) => VerifyScreen(
        extractedData: state.extra as Map<String, dynamic>?,
      ),
    ),

    // ── Transactions ─────────────────────────────────────────────────────
    GoRoute(
      path: '/manual-add',
      name: 'manual-add',
      builder: (context, state) => const ManualAddScreen(),
    ),
    GoRoute(
      path: '/transaction/:id',
      name: 'transaction',
      builder: (context, state) => TransactionDetailScreen(
        transactionID: state.pathParameters['id'] ?? '',
      ),
    ),

    // ── Subscriptions & bills ────────────────────────────────────────────
    GoRoute(
      path: '/subscriptions',
      name: 'subscriptions',
      builder: (context, state) => const SubscriptionsScreen(),
    ),
  ],
);
