import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/widgets/smartfin_logo.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _validateAndSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() {
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    bool isValid = true;
    // TLD left open-ended: the old {2,4} cap rejected real addresses on
    // .online, .company and similar before Firebase ever saw them.
    final emailRegex = RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$');

    if (email.isEmpty || !emailRegex.hasMatch(email)) {
      setState(() => _emailError = "Please enter a valid email address.");
      isValid = false;
    }

    if (password.isEmpty || password.length < 6) {
      setState(
        () => _passwordError = "Password must be at least 6 characters.",
      );
      isValid = false;
    }

    // Checked even when the password itself is invalid, so both problems surface
    // in one pass rather than one after the other.
    if (confirmPassword.isEmpty) {
      setState(() => _confirmPasswordError = "Please confirm your password.");
      isValid = false;
    } else if (confirmPassword != password) {
      setState(() => _confirmPasswordError = "Passwords do not match.");
      isValid = false;
    }

    if (!isValid) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        context.go('/setup');
      }
    } on FirebaseAuthException catch (e) {
      String message = e.message ?? "An error occurred during signup.";
      if (e.code == 'email-already-in-use') {
        message = "This email is already registered. Try logging in.";
      } else if (e.code == 'weak-password') {
        message = "Password is too weak. Use at least 6 characters.";
      } else if (e.code == 'invalid-email') {
        message = "Please enter a valid email address.";
      }

      if (mounted) {
        _showError(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
        _showError(e.message ?? 'An error occurred with Google sign-in.');
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to sign in: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppToast(context, message, error: true);
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      label,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  Widget _passwordField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String hint,
    String? errorText,
    TextInputAction action = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofillHints: const [AutofillHints.newPassword],
      textInputAction: action,
      onSubmitted: onSubmitted,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          size: 20,
          color: AppColors.textSecondary,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          color: AppColors.textSecondary,
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            semanticLabel: obscure ? 'Show password' : 'Hide password',
          ),
        ),
      ),
    );
  }

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
                    'Create your account',
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
                  _passwordField(
                    controller: _passwordController,
                    obscure: _obscurePassword,
                    onToggle: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    hint: 'At least 6 characters',
                    errorText: _passwordError,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  _fieldLabel('Confirm password'),
                  _passwordField(
                    controller: _confirmPasswordController,
                    obscure: _obscureConfirmPassword,
                    onToggle: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                    hint: 'Type it again',
                    errorText: _confirmPasswordError,
                    action: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isLoading) _validateAndSubmit();
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  AppButton(
                    label: 'Create account',
                    expand: true,
                    loading: _isLoading,
                    onPressed: _validateAndSubmit,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'By signing up, you agree to our Terms and Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(fontSize: 12),
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
                  const SizedBox(height: AppSpacing.xl),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Have an account?',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      AppButton.text(
                        label: 'Log in',
                        onPressed: () => context.push('/login'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: AppSpacing.screen,
              top: AppSpacing.sm,
              child: AppIconButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Back',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/login');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
