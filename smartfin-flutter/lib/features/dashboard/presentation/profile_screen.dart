import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/features/subscriptions/services/bill_reminder_service.dart';
import 'package:smart_fin/widgets/page_title_row.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _slipWatcherEnabled = true;
  int _budgetLimit = 0;
  String? _displayName;
  String? _photoUrl;
  int _photoVersion = 0;
  bool _isUploadingPhoto = false;
  DateTime? _memberSince;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Sequential, not concurrent: the cached values load first so the screen paints
  /// immediately, then the API response overwrites them. Running both at once let a
  /// slow prefs read land after the fresh data and clobber it.
  Future<void> _init() async {
    await _loadCachedBudget();
    await _loadProfile();
    await _loadToggles();
  }

  /// Fetches the profile from the API rather than relying on the dashboard having
  /// run first — this screen previously only read SharedPreferences, so the budget
  /// showed "Not set" whenever the cache was cold despite a real value in Mongo.
  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final res = await DioClient.dio.get('/api/users/$uid');
      final data = res.data as Map<String, dynamic>;
      final budget = ((data['budget_limit'] ?? 0) as num).toInt();
      final name = data['name'] as String?;
      final photo = data['photo_url'] as String?;
      final created = data['created_at'] as String?;

      final prefs = await SharedPreferences.getInstance();
      if (budget > 0) await prefs.setInt('user_budget_limit', budget);
      if (name != null && name.isNotEmpty) {
        await prefs.setString('user_name', name);
      }

      if (!mounted) return;
      setState(() {
        if (budget > 0) _budgetLimit = budget;
        if (name != null && name.isNotEmpty) _displayName = name;
        // Assigned unconditionally: a removed photo comes back as "", and skipping
        // the empty case would leave the stale URL rendering after a reload.
        _photoUrl = (photo?.isNotEmpty ?? false) ? photo : null;
        _memberSince = created != null ? DateTime.tryParse(created) : null;
      });
    } catch (e) {
      // Non-fatal: the locally cached budget from _loadCachedBudget still stands.
      debugPrint('Could not load profile: $e');
    }
  }

  Future<void> _loadToggles() async {
    final watcher = await GalleryWatcherService().isWatcherEnabled();
    if (!mounted) return;
    setState(() => _slipWatcherEnabled = watcher);
  }

  /// Resolves the avatar. `photo_url` is stored relative (`/api/users/<uid>/photo`)
  /// so it survives the API host changing between emulator, LAN device and
  /// deployment; a Google account's absolute URL is used as-is.
  /// Null when the user has no picture, so the caller draws a person icon —
  /// there is no placeholder image to fall back on any more.
  ImageProvider? _avatarImage() {
    final url = _photoUrl ?? FirebaseAuth.instance.currentUser?.photoURL;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return NetworkImage(url);
    // The path is stable across replacements, so without a version the cached
    // bytes would survive an upload and the picture would appear not to change.
    return NetworkImage('${DioClient.baseUrl}$url?v=$_photoVersion');
  }

  Future<void> _changePhoto() async {
    if (_isUploadingPhoto) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListRow(
                leading: const IconTile(
                  icon: Icons.photo_library_outlined,
                  color: AppColors.primary,
                ),
                title: 'Choose from gallery',
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListRow(
                leading: const IconTile(
                  icon: Icons.photo_camera_outlined,
                  color: AppColors.primary,
                ),
                title: 'Take a photo',
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              if (_photoUrl != null && _photoUrl!.isNotEmpty)
                ListRow(
                  leading: const IconTile(
                    icon: Icons.delete_outline_rounded,
                    color: AppColors.danger,
                  ),
                  title: 'Remove photo',
                  titleColor: AppColors.danger,
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'remove') {
      await _removePhoto();
      return;
    }
    await _uploadPhoto(
      choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
  }

  Future<void> _uploadPhoto(ImageSource source) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    try {
      // Downscale before upload: a modern camera frame is several MB and the
      // avatar renders at 96px.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() => _isUploadingPhoto = true);

      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          picked.path,
          filename: picked.path.split('/').last,
        ),
      });
      final res = await DioClient.dio.post(
        '/api/users/$uid/photo',
        data: formData,
      );
      final path = (res.data as Map<String, dynamic>)['photo_url'] as String?;

      if (!mounted) return;
      setState(() {
        _photoUrl = path;
        _photoVersion = DateTime.now().millisecondsSinceEpoch;
      });
      _toast('Photo updated');
    } on DioException catch (e) {
      if (mounted) _toast(DioClient.handleError(e), error: true);
    } catch (e) {
      if (mounted) _toast('Could not update photo: $e', error: true);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    setState(() => _isUploadingPhoto = true);
    try {
      await DioClient.dio.delete('/api/users/$uid/photo');
      if (!mounted) return;
      setState(() {
        _photoUrl = null;
        _photoVersion = DateTime.now().millisecondsSinceEpoch;
      });
      _toast('Photo removed');
    } on DioException catch (e) {
      if (mounted) _toast(DioClient.handleError(e), error: true);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, message, error: error);
  }

  String _memberSinceLabel() {
    final joined =
        _memberSince ??
        FirebaseAuth.instance.currentUser?.metadata.creationTime;
    if (joined == null) return 'SmartFin Member';
    return 'SmartFin Member since ${DateFormat('MMM yyyy').format(joined.toLocal())}';
  }

  Future<void> _loadCachedBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final budget = prefs.getInt('user_budget_limit') ?? 0;
    if (mounted) setState(() => _budgetLimit = budget);
  }

  Future<void> _showBudgetEditor() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BudgetEditorSheet(
        currentBudget: _budgetLimit,
        scaffoldContext: context,
      ),
    );
    if (result != null && mounted) {
      setState(() => _budgetLimit = result);
      _toast('Budget updated');
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          "You'll need to sign in again to see your spending.",
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
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () async {
              // Taken before the awaits below, which can outlive this screen.
              final router = GoRouter.of(context);
              Navigator.pop(ctx);
              // Don't remind the next person on this device about these bills.
              await BillReminderService().cancelAll();
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              // The income keys are no longer written; they stay here so a phone
              // that ran an older build is cleaned up on logout.
              for (final key in const [
                'user_name',
                'user_income',
                'user_status',
                'user_health',
                'user_income_amount',
                'user_budget_limit',
                'income_set',
                'income_prompt_dismissed',
                'setup_complete',
                'onboarding_complete',
              ]) {
                await prefs.remove(key);
              }
              router.go('/login');
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  String get _budgetLabel => _budgetLimit > 0
      ? '฿${_budgetLimit.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}'
      : 'Not set';

  static const Widget _chevron = Icon(
    Icons.chevron_right_rounded,
    color: AppColors.textMuted,
  );

  /// A settings row: neutral icon tile, label, and what is on the right.
  Widget _settingsRow({
    required IconData icon,
    required String label,
    String? subtitle,
    Widget trailing = _chevron,
    VoidCallback? onTap,
  }) {
    return ListRow(
      leading: IconTile(icon: icon, color: AppColors.textSecondary),
      title: label,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 14,
      ),
    );
  }

  Widget _groupLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  Widget _buildAvatar() {
    final avatar = _avatarImage();
    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        onTap: _changePhoto,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceMuted,
                border: Border.all(color: AppColors.white, width: 4),
                boxShadow: AppShadows.card,
                image: avatar == null
                    ? null
                    : DecorationImage(
                        image: avatar,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
              child: _isUploadingPhoto
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.fromRGBO(0, 0, 0, 0.35),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    )
                  : (avatar == null
                        ? const Icon(
                            Icons.person_outline_rounded,
                            size: 44,
                            color: AppColors.textSecondary,
                          )
                        : null),
            ),
            // Affordance: without it the avatar reads as decoration.
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cream, width: 3),
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  size: 14,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      // Expand, so what is pinned to the bottom stays there when the content
      // is shorter than the screen.
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            // Header content ends at 48 + 40; the list starts 16 below it.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              104,
              AppSpacing.screen,
              120,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Who ─────────────────────────────────────────────────
                Center(child: _buildAvatar()),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _displayName ??
                      FirebaseAuth.instance.currentUser?.displayName ??
                      'User',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 2),
                Text(
                  _memberSinceLabel(),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),

                const SizedBox(height: AppSpacing.xxl),

                // ── Money ───────────────────────────────────────────────
                _groupLabel('Money'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _settingsRow(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Monthly budget',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                _budgetLabel,
                                style: AppTextStyles.label.copyWith(
                                  color: AppColors.primaryText,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            _chevron,
                          ],
                        ),
                        onTap: _showBudgetEditor,
                      ),
                      ListRow.divider(),
                      _settingsRow(
                        icon: Icons.event_repeat_outlined,
                        label: 'Subscriptions & bills',
                        // push, not go: a subscreen, so back returns here.
                        onTap: () => context.push<bool>('/subscriptions'),
                      ),
                      ListRow.divider(),
                      _settingsRow(
                        icon: Icons.document_scanner_outlined,
                        label: 'Auto-Detect slips',
                        subtitle: 'Spot new slips in your photos',
                        trailing: Switch(
                          value: _slipWatcherEnabled,
                          onChanged: (val) async {
                            setState(() => _slipWatcherEnabled = val);
                            await GalleryWatcherService().setWatcherEnabled(
                              val,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Account ─────────────────────────────────────────────
                _groupLabel('Account'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _settingsRow(
                        icon: Icons.person_outline_rounded,
                        label: 'Account settings',
                        onTap: () async {
                          // push, not go: this is a subscreen, so back must
                          // return here rather than exiting the app.
                          final changed = await context.push<bool>(
                            '/account-settings',
                          );
                          if (changed == true) await _init();
                        },
                      ),
                      ListRow.divider(),
                      _settingsRow(
                        icon: Icons.shield_outlined,
                        label: 'Security & privacy',
                        onTap: () => context.push('/security-privacy'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                AppCard(
                  padding: EdgeInsets.zero,
                  flat: true,
                  child: ListRow(
                    leading: const IconTile(
                      icon: Icons.logout_rounded,
                      color: AppColors.danger,
                    ),
                    title: 'Log out',
                    titleColor: AppColors.danger,
                    onTap: _showLogoutDialog,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sticky header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                child: Container(
                  color: AppColors.cream.withValues(alpha: 0.85),
                  padding: const EdgeInsets.only(
                    left: AppSpacing.screen,
                    right: AppSpacing.screen,
                    top: 48,
                    bottom: AppSpacing.sm,
                  ),
                  child: const PageTitleRow(title: 'Profile'),
                ),
              ),
            ),
          ),

          // Bottom Nav
          const SmartFinBottomNav(currentIndex: 3),
        ],
      ),
    );
  }
}

// ── Budget Editor Bottom Sheet ────────────────────────────────────────────────

class _BudgetEditorSheet extends StatefulWidget {
  final int currentBudget;
  final BuildContext scaffoldContext;

  const _BudgetEditorSheet({
    required this.currentBudget,
    required this.scaffoldContext,
  });

  @override
  State<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends State<_BudgetEditorSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    if (widget.currentBudget > 0) {
      _amountController.text = widget.currentBudget.toString();
    }
    _amountController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cursorController.dispose();
    _amountController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _formattedAmount {
    final clean = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) return '0';
    return clean.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  void _showError(String msg) =>
      showAppToast(widget.scaffoldContext, msg, error: true);

  Future<void> _saveBudget() async {
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(raw) ?? 0;

    if (amount <= 0) {
      _showError('Please enter a budget amount');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await DioClient.dio.put(
        '/api/users/$uid',
        data: {'budget_limit': amount},
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_budget_limit', amount);

      if (mounted) Navigator.pop(context, amount);
    } on DioException catch (e) {
      _showError('Failed to save: ${e.message}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Monthly budget',
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'How much you want to allow yourself to spend each month.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Amount display with blinking cursor
              Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '฿',
                        style: AppTextStyles.display.copyWith(
                          fontSize: 40,
                          color: AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formattedAmount,
                        style: AppTextStyles.display.copyWith(fontSize: 40),
                      ),
                      const SizedBox(width: 4),
                      FadeTransition(
                        opacity: _cursorController,
                        child: Container(
                          width: 2,
                          height: 40,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  // Hidden auto-focused TextField
                  Positioned.fill(
                    child: TextField(
                      controller: _amountController,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      showCursor: false,
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 1,
                      ),
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              AppButton(
                label: 'Save budget',
                expand: true,
                loading: _isSaving,
                onPressed: _saveBudget,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton.text(
                label: 'Maybe later',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
