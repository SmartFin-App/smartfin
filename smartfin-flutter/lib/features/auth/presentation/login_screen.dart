import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/widgets/smartfin_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _validateAndSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    bool isValid = true;
    // TLD left open-ended: the old {2,4} cap rejected real addresses on
    // .online, .company and similar before Firebase ever saw them.
    final emailRegex = RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$');

    if (email.isEmpty || !emailRegex.hasMatch(email)) {
      setState(() => _emailError = "Please enter a valid email address.");
      isValid = false;
    }

    if (password.isEmpty) {
      setState(() => _passwordError = "Please enter your password.");
      isValid = false;
    }

    if (!isValid) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        context.go('/home');
      }
    } on FirebaseAuthException catch (e) {
      String message = e.message ?? "An error occurred during login.";
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        message = "Incorrect email or password.";
      } else if (e.code == 'invalid-email') {
        message = "Please enter a valid email address.";
      }

      if (mounted) {
        _showSnack(message, error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Sends a Firebase password-reset email.
  ///
  /// Prefills the dialog with whatever is already typed in the email field, and
  /// reports success the same way whether or not the address has an account —
  /// telling a stranger which emails are registered is a disclosure we do not
  /// need to make.
  Future<void> _sendPasswordReset() async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset your password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('We will email you a link to choose a new password.'),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: AppTextStyles.body,
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                prefixIcon: Icon(
                  Icons.mail_outline_rounded,
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );

    if (email == null || !mounted) return;

    final emailRegex = RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      _showSnack('Please enter a valid email address.', error: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        _showSnack('If that email has an account, a reset link is on its way.');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // user-not-found is deliberately reported as success above; anything else
      // is a real failure worth naming.
      if (e.code == 'user-not-found') {
        _showSnack('If that email has an account, a reset link is on its way.');
      } else if (e.code == 'invalid-email') {
        _showSnack('Please enter a valid email address.', error: true);
      } else if (e.code == 'too-many-requests') {
        _showSnack(
          'Too many attempts. Please try again in a few minutes.',
          error: true,
        );
      } else {
        _showSnack(e.message ?? 'Could not send the reset email.', error: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Could not send the reset email: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, message, error: error);
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isGoogleLoading = false);
        return; // User canceled
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      if (mounted) {
        if (userCredential.additionalUserInfo?.isNewUser ?? false) {
          context.go('/setup');
        } else {
          context.go('/home');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _showSnack(
          e.message ?? 'An error occurred with Google sign-in.',
          error: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to sign in: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      label,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                72,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 700),
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.scale(
                          scale: 0.8 + (0.2 * value),
                          child: child,
                        ),
                      );
                    },
                    child: const Center(child: SmartFinLogo(fontSize: 32)),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.title,
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  _fieldLabel('Email'),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: 'you@example.com',
                      errorText: _emailError,
                      prefixIcon: const Icon(
                        Icons.mail_outline_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  _fieldLabel('Password'),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isLoading) _validateAndSubmit();
                    },
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: 'Your password',
                      errorText: _passwordError,
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        color: AppColors.textSecondary,
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          semanticLabel: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton.text(
                      label: 'Forgot password?',
                      onPressed: _isLoading ? null : _sendPasswordReset,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  AppButton(
                    label: 'Log in',
                    expand: true,
                    loading: _isLoading,
                    onPressed: _validateAndSubmit,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: Text('or', style: AppTextStyles.caption),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
                      child: _isGoogleLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/images/google_logo.png',
                                  width: 18,
                                  height: 18,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                const Text('Continue with Google'),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'New to SmartFin?',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      AppButton.text(
                        label: 'Sign up',
                        onPressed: () => context.push('/signup'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Login is where the splash lands a signed-out user, so there is
            // usually nothing behind it; the arrow only shows when it was
            // pushed from somewhere, such as the signup screen.
            if (context.canPop())
              Positioned(
                left: AppSpacing.screen,
                top: AppSpacing.sm,
                child: AppIconButton(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: 'Back',
                  onPressed: () => context.pop(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
