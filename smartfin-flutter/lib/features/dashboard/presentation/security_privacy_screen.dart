import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
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
    showAppToast(context, message, error: error);
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
      _toast(
        'This sign-in method cannot be reauthenticated in the app',
        error: true,
      );
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
        title: const Text('Confirm it is you'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter your current password to $purpose.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Current password',
                prefixIcon: Icon(
                  Icons.lock_outline_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirm'),
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
      _toast('Password updated');
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
          title: const Text('New password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'New password',
                  prefixIcon: const Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
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
                  prefixIcon: const Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Cancel'),
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
              child: const Text('Update'),
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
      _toast(
        'Could not delete your data: ${DioClient.handleError(e)}',
        error: true,
      );
    } on FirebaseAuthException catch (e) {
      // The records are already gone at this point, so be explicit rather than
      // letting the user think nothing happened.
      _toast(
        'Your data was deleted, but the login could not be removed: '
        '${_authMessage(e)}',
        error: true,
      );
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
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently erases your profile, every expense, your monthly '
          'summaries and your AI Coach conversations. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text, {Color color = AppColors.textSecondary}) =>
      Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.xs,
          bottom: AppSpacing.sm,
        ),
        child: Text(text, style: AppTextStyles.label.copyWith(color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final method = _hasPasswordProvider
        ? 'Email and password'
        : _hasGoogleProvider
        ? 'Google'
        : 'Unknown';
    const chevron = Icon(
      Icons.chevron_right_rounded,
      color: AppColors.textMuted,
    );

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              SubpageHeader.contentTop,
              AppSpacing.screen,
              60,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionLabel('Sign-in method'),
                AppCard(
                  flat: true,
                  padding: EdgeInsets.zero,
                  child: ListRow(
                    leading: IconTile(
                      icon: _hasGoogleProvider
                          ? Icons.g_mobiledata_rounded
                          : Icons.mail_outline_rounded,
                      color: AppColors.textSecondary,
                    ),
                    title: method,
                    subtitle: _user?.email,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                _sectionLabel('Security'),
                if (_hasPasswordProvider)
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: ListRow(
                      leading: const IconTile(
                        icon: Icons.lock_outline_rounded,
                        color: AppColors.textSecondary,
                      ),
                      title: 'Change password',
                      subtitle: 'Verify your current password first',
                      trailing: chevron,
                      onTap: _isBusy ? null : _changePassword,
                    ),
                  )
                else
                  AppCard(
                    flat: true,
                    child: Text(
                      'Your password is managed by Google, so it cannot be changed here.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),

                _sectionLabel('Danger zone', color: AppColors.danger),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListRow(
                    leading: const IconTile(
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.danger,
                    ),
                    title: 'Delete account',
                    titleColor: AppColors.danger,
                    subtitle: 'Erases your expenses and chats',
                    trailing: chevron,
                    onTap: _isBusy ? null : _deleteAccount,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    'Deleting removes your data from SmartFin permanently. There is no recovery.',
                    style: AppTextStyles.caption.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          SubpageHeader(
            title: 'Security & privacy',
            onBack: () => context.pop(),
          ),
          if (_isBusy)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.cream.withValues(alpha: 0.6),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
