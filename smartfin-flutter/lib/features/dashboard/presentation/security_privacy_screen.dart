import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/subscriptions/services/bill_reminder_service.dart';

/// Security actions that need a recent login: changing the password and deleting
/// the account. Firebase rejects both with `requires-recent-login` when the session
/// is stale, so each is gated behind an explicit reauthentication step.
class SecurityPrivacyScreen extends StatefulWidget {
  const SecurityPrivacyScreen({super.key});

  @override
  State<SecurityPrivacyScreen> createState() => _SecurityPrivacyScreenState();
}

class _SecurityPrivacyScreenState extends State<SecurityPrivacyScreen> {
  bool _isBusy = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  /// Google accounts have no password to change, and reauthenticate through the
  /// Google sheet instead of a password prompt.
  bool get _hasPasswordProvider =>
      _user?.providerData.any((p) => p.providerId == 'password') ?? false;

  bool get _hasGoogleProvider =>
      _user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// Prompts for credentials and verifies them against Firebase, so callers know
  /// the identity is confirmed *before* asking for anything else. Returns false
  /// when the user cancels or the credentials are wrong, having already surfaced
  /// the reason.
  Future<bool> _reauthenticate({required String purpose}) async {
    final user = _user;
    if (user == null) {
      _toast('You need to be signed in', error: true);
      return false;
    }

    AuthCredential credential;
    if (_hasPasswordProvider) {
      final password = await _promptForPassword(purpose: purpose);
      if (password == null || password.isEmpty) return false; // cancelled
      credential = EmailAuthProvider.credential(
        email: user.email ?? '',
        password: password,
      );
    } else if (_hasGoogleProvider) {
      try {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return false; // cancelled
        final googleAuth = await googleUser.authentication;
        credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
      } catch (e) {
        _toast('Could not verify it is you: $e', error: true);
        return false;
      }
    } else {
      _toast('This sign-in method cannot be reauthenticated in the app',
          error: true);
      return false;
    }

    // Only the network round-trip shows the overlay; the prompt above must not be
    // covered by it.
    if (mounted) setState(() => _isBusy = true);
    try {
      await user.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      _toast(_authMessage(e), error: true);
      return false;
    } catch (e) {
      _toast('Could not verify it is you: $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'That password is not correct.';
      case 'weak-password':
        return 'Please choose a stronger password (at least 6 characters).';
      case 'requires-recent-login':
        return 'Please sign in again before making this change.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'user-mismatch':
        return 'Those credentials belong to a different account.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  Future<String?> _promptForPassword({required String purpose}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirm it is you',
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w800,
            fontSize: 19,
            color: const Color(0xFF333333),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your current password to $purpose.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Current password',
                filled: true,
                fillColor: const Color.fromRGBO(240, 235, 225, 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: const Color(0xFF9E9E9E))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Confirm',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: const Color(0xFFFF9F29))),
          ),
        ],
      ),
    );
  }

  // ── Change password ────────────────────────────────────────────────────────

  Future<void> _changePassword() async {
    if (_isBusy) return;

    // Current password first, verified against Firebase before we go any further.
    // Asking for the new one up front would make the user type it twice only to
    // discard it when the old password turns out to be wrong.
    if (!await _reauthenticate(purpose: 'change your password')) return;

    final newPassword = await _promptForNewPassword();
    if (newPassword == null) return;

    setState(() => _isBusy = true);
    try {
      await _user!.updatePassword(newPassword);
      _toast('Password updated 🐾');
    } on FirebaseAuthException catch (e) {
      _toast(_authMessage(e), error: true);
    } catch (e) {
      _toast('Could not update password: $e', error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<String?> _promptForNewPassword() {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'New password',
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w800,
              fontSize: 19,
              color: const Color(0xFF333333),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'New password',
                  filled: true,
                  fillColor: const Color.fromRGBO(240, 235, 225, 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Confirm new password',
                  errorText: error,
                  filled: true,
                  fillColor: const Color.fromRGBO(240, 235, 225, 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9E9E9E))),
            ),
            TextButton(
              onPressed: () {
                if (passwordController.text.length < 6) {
                  setDialogState(() => error = 'At least 6 characters');
                  return;
                }
                if (passwordController.text != confirmController.text) {
                  setDialogState(() => error = 'Passwords do not match');
                  return;
                }
                Navigator.pop(ctx, passwordController.text);
              },
              child: Text('Update',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFF9F29))),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete account ─────────────────────────────────────────────────────────

  Future<void> _deleteAccount() async {
    if (_isBusy) return;

    if (!await _confirmDeletion()) return;
    if (!await _reauthenticate(purpose: 'delete your account')) return;

    setState(() => _isBusy = true);
    try {
      final uid = _user?.uid ?? '';
      if (uid.isEmpty) {
        _toast('You need to be signed in', error: true);
        return;
      }

      // Owned records first: a failure here leaves the account intact and
      // retryable, whereas deleting the login first would strand the data with no
      // way to reach it.
      await DioClient.dio.delete('/api/users/$uid');
      await BillReminderService().cancelAll();
      await _user!.delete();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      _toast('Your account and data have been deleted');
      context.go('/login');
    } on DioException catch (e) {
      _toast('Could not delete your data: ${DioClient.handleError(e)}',
          error: true);
    } on FirebaseAuthException catch (e) {
      // The records are already gone at this point, so be explicit rather than
      // letting the user think nothing happened.
      _toast('Your data was deleted, but the login could not be removed: '
          '${_authMessage(e)}',
          error: true);
    } catch (e) {
      _toast('Could not delete account: $e', error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _confirmDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete account?',
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: const Color(0xFFEF4444),
          ),
        ),
        content: Text(
          'This permanently erases your profile, every transaction, your monthly '
          'summaries and your coach conversations. It cannot be undone.',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.5,
            color: const Color(0xFF9E9E9E),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: const Color(0xFF9E9E9E))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete everything',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final method = _hasPasswordProvider
        ? 'Email and password'
        : _hasGoogleProvider
            ? 'Google'
            : 'Unknown';

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(top: 130, bottom: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('SIGN-IN METHOD'),
                  const SizedBox(height: 12),
                  _card(
                    child: Row(
                      children: [
                        Icon(
                          _hasGoogleProvider
                              ? Icons.g_mobiledata
                              : Icons.mail_outline,
                          size: 20,
                          color: const Color(0xFF9E9E9E),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                method,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: const Color(0xFF333333),
                                ),
                              ),
                              if ((_user?.email ?? '').isNotEmpty)
                                Text(
                                  _user!.email!,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    color: const Color(0xFF9E9E9E),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  _sectionLabel('SECURITY'),
                  const SizedBox(height: 12),
                  if (_hasPasswordProvider)
                    _actionCard(
                      icon: Icons.lock_outline,
                      title: 'Change password',
                      subtitle: 'Confirm your current password, then set a new one',
                      onTap: _changePassword,
                    )
                  else
                    _card(
                      child: Text(
                        'Your password is managed by Google, so it cannot be '
                        'changed here.',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          height: 1.5,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),

                  _sectionLabel('DANGER ZONE'),
                  const SizedBox(height: 12),
                  _actionCard(
                    icon: Icons.delete_outline,
                    title: 'Delete account',
                    subtitle: 'Erases your profile, transactions and chat history',
                    danger: true,
                    onTap: _deleteAccount,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Deleting removes your data from SmartFin permanently. There '
                    'is no recovery.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      height: 1.5,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildHeader(),
          if (_isBusy)
            Positioned.fill(
              child: Container(
                color: const Color.fromRGBO(255, 249, 240, 0.6),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF9F29)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 2,
          color: const Color(0xFF9E9E9E),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.5)),
      ),
      child: child,
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final accent = danger ? const Color(0xFFEF4444) : const Color(0xFF333333);
    return InkWell(
      onTap: _isBusy ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: danger
                ? const Color.fromRGBO(239, 68, 68, 0.2)
                : const Color.fromRGBO(234, 226, 214, 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
          child: Container(
            color: const Color.fromRGBO(255, 249, 240, 0.8),
            padding:
                const EdgeInsets.only(left: 24, right: 24, top: 48, bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color.fromRGBO(234, 226, 214, 0.6)),
                    ),
                    child: const Icon(Icons.chevron_left,
                        size: 22, color: Color.fromRGBO(51, 51, 51, 0.7)),
                  ),
                ),
                Text(
                  'Security & Privacy',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
