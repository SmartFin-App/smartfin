import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/network/dio_client.dart';

/// Editor for the profile attributes captured once during onboarding and never
/// editable afterwards. These are not cosmetic: the orchestrator injects income
/// bracket, current status and financial health into the coach's system prompt, so
/// a stale "Student / Paycheck to Paycheck" quietly skews every piece of advice.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  static const _statuses = ['Student', 'Pro', 'Founder'];
  static const _healthOptions = [
    'Debt-Free',
    'Saving Up',
    'Managing Debt',
    'Paycheck to Paycheck',
  ];

  final TextEditingController _nameController = TextEditingController();

  String? _status;
  String? _health;
  String _email = '';

  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    _email = user?.email ?? '';

    // Paint cached values first so the form is usable even if the request is slow.
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameController.text =
            prefs.getString('user_name') ?? user?.displayName ?? '';
        _status = prefs.getString('user_status');
        _health = prefs.getString('user_health');
      });
    }

    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
      return;
    }

    try {
      final res = await DioClient.dio.get('/api/users/$uid');
      final data = res.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        final name = data['name'] as String?;
        if (name != null && name.isNotEmpty) _nameController.text = name;
        _email = (data['email'] as String?)?.isNotEmpty == true
            ? data['email'] as String
            : _email;
        _status = _valueOrNull(data['current_status'], _statuses) ?? _status;
        _health = _valueOrNull(data['financial_health'], _healthOptions) ?? _health;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Could not load account settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Cached values may still be usable; only flag a hard failure when the
          // form would otherwise be empty.
          _loadFailed = _nameController.text.isEmpty && _status == null;
        });
      }
    }
  }

  /// Keeps a stored value only when it is one this screen can actually render, so
  /// an unrecognised bracket can't leave a pill group with nothing selected.
  String? _valueOrNull(dynamic raw, List<String> allowed) {
    final value = raw as String?;
    if (value == null || value.isEmpty) return null;
    return allowed.contains(value) ? value : null;
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Please enter your name', error: true);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _toast('You need to be signed in to save changes', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // No income bracket here: it is derived from the exact monthly income, which
      // is edited in Profile. A separate picker let the two contradict each other
      // ("Under 20k" beside an income of ฿80,000).
      await DioClient.dio.put('/api/users/$uid', data: {
        'name': name,
        if (_status != null) 'current_status': _status,
        if (_health != null) 'financial_health': _health,
      });

      // Keep Firebase's displayName in step — the profile header and the coach's
      // greeting both read it rather than the backend record.
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.displayName != name) {
        await user.updateDisplayName(name);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', name);
      if (_status != null) await prefs.setString('user_status', _status!);
      if (_health != null) await prefs.setString('user_health', _health!);

      if (!mounted) return;
      _toast('Account updated! 🐾');
      context.pop(true);
    } on DioException catch (e) {
      if (mounted) _toast('Failed to save: ${DioClient.handleError(e)}', error: true);
    } catch (e) {
      if (mounted) _toast('Failed to save: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFFFF9F29)))
          else if (_loadFailed)
            _buildFailureState()
          else
            SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(top: 130, bottom: 140),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('YOUR NAME'),
                    const SizedBox(height: 12),
                    _card(
                      child: TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF333333),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Your name',
                          hintStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            color: const Color(0xFFBDBDBD),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    _sectionLabel('EMAIL'),
                    const SizedBox(height: 12),
                    _card(
                      child: Row(
                        children: [
                          const Icon(Icons.mail_outline,
                              size: 18, color: Color(0xFF9E9E9E)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _email.isEmpty ? 'No email on this account' : _email,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: const Color(0xFF9E9E9E),
                              ),
                            ),
                          ),
                          const Icon(Icons.lock_outline,
                              size: 16, color: Color(0xFFBDBDBD)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    _sectionLabel('CURRENT STATUS'),
                    const SizedBox(height: 12),
                    _pillGroup(
                        _statuses, _status, (v) => setState(() => _status = v)),
                    const SizedBox(height: 28),

                    _sectionLabel('FINANCIAL HEALTH'),
                    const SizedBox(height: 12),
                    _pillGroup(_healthOptions, _health,
                        (v) => setState(() => _health = v)),
                    const SizedBox(height: 16),

                    Text(
                      'Your coach uses these to tailor its advice.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: const Color(0xFF9E9E9E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _buildHeader(),
          if (!_isLoading && !_loadFailed) _buildSaveBar(),
        ],
      ),
    );
  }

  Widget _buildFailureState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFF9E9E9E), size: 32),
            const SizedBox(height: 16),
            Text(
              "Couldn't load your account",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isLoading = true;
                  _loadFailed = false;
                });
                _load();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F29),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  'TRY AGAIN',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
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

  Widget _pillGroup(
      List<String> options, String? selected, ValueChanged<String> onSelect) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) => _pill(o, selected, onSelect)).toList(),
    );
  }

  Widget _pill(String text, String? groupValue, ValueChanged<String> onSelect) {
    final bool isSelected = text == groupValue;
    return GestureDetector(
      onTap: () => onSelect(text),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color.fromRGBO(255, 159, 41, 0.05)
              : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFFEAE2D6),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
            fontSize: 14,
            color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFF333333),
          ),
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
            padding: const EdgeInsets.only(
                left: 24, right: 24, top: 48, bottom: 24),
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
                  'Account Settings',
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

  Widget _buildSaveBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xFFFFF9F0)],
          ),
        ),
        child: GestureDetector(
          onTap: _isSaving ? null : _save,
          child: Container(
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9F29),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    'SAVE CHANGES',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
