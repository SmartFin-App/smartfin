import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    final controller = TextEditingController(text: _emailController.text.trim());

    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Reset your password',
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
              'We will email you a link to choose a new password.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'you@example.com',
                filled: true,
                fillColor: const Color.fromRGBO(240, 235, 225, 0.35),
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
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF9E9E9E)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(
              'Send link',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFFFF9F29)),
            ),
          ),
        ],
      ),
    );

    if (email == null || !mounted) return;

    final emailRegex = RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      _showSnack('Please enter a valid email address.');
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
        _showSnack('Please enter a valid email address.');
      } else if (e.code == 'too-many-requests') {
        _showSnack('Too many attempts. Please try again in a few minutes.');
      } else {
        _showSnack(e.message ?? 'Could not send the reset email.');
      }
    } catch (e) {
      if (mounted) _showSnack('Could not send the reset email: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isGoogleLoading = false);
        return; // User canceled
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        if (userCredential.additionalUserInfo?.isNewUser ?? false) {
          context.go('/setup');
        } else {
          context.go('/home');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "An error occurred with Google Sign-In.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to sign in: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Widget _buildFieldLabel(String label) {
    return Container(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: 9,
          letterSpacing: 2,
          color: const Color(0xFF9E9E9E),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    bool isPassword = false,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: errorText != null ? Colors.red : const Color(0xFFEAE2D6)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword ? _obscurePassword : false,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: const Color(0xFF333333),
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: isPassword
                  ? GestureDetector(
                      onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                      child: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: const Color(0xFF9E9E9E),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: const Color(0xFFEF4444),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // Scrollable Content
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 112, bottom: 48, left: 24, right: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Cat
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 700),
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.scale(scale: 0.8 + (0.2 * value), child: child),
                    );
                  },
                  child: const SmartFinLogo(fontSize: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  'WELCOME BACK',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
                const SizedBox(height: 32),

                // Email Field
                _buildFieldLabel('EMAIL ADDRESS'),
                const SizedBox(height: 8),
                _buildTextField(controller: _emailController, errorText: _emailError),
                const SizedBox(height: 24),

                // Password Field
                _buildFieldLabel('PASSWORD'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _passwordController,
                  isPassword: true,
                  errorText: _passwordError,
                ),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _isLoading ? null : _sendPasswordReset,
                    child: Text(
                      'Forgot Password?',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: const Color(0xFFFF9F29),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Log In Button
                GestureDetector(
                  onTap: _isLoading ? null : _validateAndSubmit,
                  child: Container(
                    width: double.infinity,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9F29),
                      borderRadius: BorderRadius.circular(9999),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF9F29).withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'LOG IN',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 2.4,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 32),

                // Divider
                Row(
                  children: [
                    Expanded(
                      child: Container(height: 1, color: const Color.fromRGBO(234, 226, 214, 0.4)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'QUICK CONNECT',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 2,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(height: 1, color: const Color.fromRGBO(234, 226, 214, 0.4)),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Google Button
                GestureDetector(
                  onTap: _isGoogleLoading ? null : _handleGoogleSignIn,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFEAE2D6)),
                      borderRadius: BorderRadius.circular(9999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isGoogleLoading
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Color(0xFF333333),
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset('assets/images/google_logo.png', width: 16, height: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Google',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: const Color(0xFF333333),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 48),

                // Bottom Nav
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'New to SmartFin?',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: const Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => context.push('/signup'),
                      child: Text(
                        'Sign Up',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: const Color(0xFFFF9F29),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: Container(
                  height: 92,
                  color: const Color.fromRGBO(255, 249, 240, 0.8),
                  child: Stack(
                    children: [
                      // Login is where the splash lands a signed-out user, so there
                      // is usually nothing behind it; the arrow only shows when it
                      // was pushed from somewhere, such as the signup screen.
                      if (context.canPop())
                        Positioned(
                          left: 24,
                          top: 40,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => context.pop(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.chevron_left,
                                color: Color(0xFF333333),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
