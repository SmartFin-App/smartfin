import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/core/network/dio_client.dart';

/// Editor for the profile attributes captured once during onboarding and never
/// editable afterwards. These are not cosmetic: the orchestrator puts the name and
/// financial health into the coach's system prompt, so a stale "Paycheck to
/// Paycheck" quietly skews every piece of advice.
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
        _health =
            _valueOrNull(data['financial_health'], _healthOptions) ?? _health;
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

  void _toast(String message, {bool error = false}) =>
      showAppToast(context, message, error: error);

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
      await DioClient.dio.put(
        '/api/users/$uid',
        data: {
          'name': name,
          if (_status != null) 'current_status': _status,
          if (_health != null) 'financial_health': _health,
        },
      );

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
      _toast('Account updated');
      context.pop(true);
    } on DioException catch (e) {
      if (mounted) {
        _toast('Failed to save: ${DioClient.handleError(e)}', error: true);
      }
    } catch (e) {
      if (mounted) _toast('Failed to save: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static const Map<String, IconData> _statusIcons = {
    'Student': Icons.school_outlined,
    'Pro': Icons.work_outline,
    'Founder': Icons.rocket_launch_outlined,
  };

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      // Expand, so the save bar pins to the screen's bottom: a short form's
      // scroll view would otherwise size the stack to its content.
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_loadFailed)
            Center(
              child: StatusMessage(
                icon: Icons.cloud_off_rounded,
                title: "Couldn't load your account",
                message: 'Check your connection, then try again.',
                action: AppButton.secondary(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _loadFailed = false;
                    });
                    _load();
                  },
                ),
              ),
            )
          else
            SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                SubpageHeader.contentTop,
                AppSpacing.screen,
                140,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionLabel('Your name'),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: AppTextStyles.body,
                    decoration: const InputDecoration(
                      hintText: 'Your name',
                      prefixIcon: Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _sectionLabel('Email'),
                  // Read-only: the email is the Firebase login, changed there.
                  AppCard(
                    flat: true,
                    padding: EdgeInsets.zero,
                    color: AppColors.surfaceMuted,
                    child: ListRow(
                      leading: const Icon(
                        Icons.mail_outline_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      title: _email.isEmpty
                          ? 'No email on this account'
                          : _email,
                      titleColor: AppColors.textSecondary,
                      trailing: const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _sectionLabel('What do you do?'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final s in _statuses)
                        AppChip(
                          label: s,
                          icon: _statusIcons[s],
                          selected: _status == s,
                          onTap: () => setState(() => _status = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _sectionLabel('How are your finances?'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final h in _healthOptions)
                        AppChip(
                          label: h,
                          selected: _health == h,
                          onTap: () => setState(() => _health = h),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Your AI Coach uses these to tailor its advice.',
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          SubpageHeader(title: 'Account settings', onBack: () => context.pop()),
          if (!_isLoading && !_loadFailed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.cream.withValues(alpha: 0),
                      AppColors.cream,
                    ],
                    stops: const [0, 0.35],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.xxl,
                  AppSpacing.screen,
                  32,
                ),
                child: AppButton(
                  label: 'Save changes',
                  expand: true,
                  loading: _isSaving,
                  onPressed: _save,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
