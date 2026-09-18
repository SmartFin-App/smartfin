import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/features/subscriptions/services/bill_reminder_service.dart';
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
      if (name != null && name.isNotEmpty) await prefs.setString('user_name', name);

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

  /// Resolves the avatar. `photo_url` is stored relative ("/api/users/<uid>/photo")
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFEAE2D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFFFF9F29)),
              title: Text('Choose from gallery',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_outlined, color: Color(0xFFFF9F29)),
              title: Text('Take a photo',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (_photoUrl != null && _photoUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                title: Text('Remove photo',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFEF4444))),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'remove') {
      await _removePhoto();
      return;
    }
    await _uploadPhoto(
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
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
      final res = await DioClient.dio.post('/api/users/$uid/photo', data: formData);
      final path = (res.data as Map<String, dynamic>)['photo_url'] as String?;

      if (!mounted) return;
      setState(() {
        _photoUrl = path;
        _photoVersion = DateTime.now().millisecondsSinceEpoch;
      });
      _toast('Photo updated 🐾');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String _memberSinceLabel() {
    final joined = _memberSince ?? FirebaseAuth.instance.currentUser?.metadata.creationTime;
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
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetEditorSheet(
        currentBudget: _budgetLimit,
        scaffoldContext: context,
      ),
    );
    if (result != null && mounted) {
      setState(() => _budgetLimit = result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Budget updated! 🐾',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Log Out",
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: const Color(0xFF333333),
          ),
        ),
        content: Text(
          "Are you sure you want to log out?",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: const Color(0xFF9E9E9E),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9E9E9E),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
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
              if (context.mounted) context.go('/login');
            },
            child: Text(
              "Log Out",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(240, 235, 225, 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: const Color.fromRGBO(51, 51, 51, 0.6)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter( // fallback to Inter for strong legibility
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: const Color(0xFF333333),
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(top: 130, bottom: 120),
            child: Column(
              children: [
                // Section 1 - User Info
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: _changePhoto,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.5), width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Builder(builder: (context) {
                                final avatar = _avatarImage();
                                return Container(
                                width: 96,
                                height: 96,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  color: const Color(0xFFF0EBE1),
                                  border: Border.all(color: Colors.white, width: 4),
                                  image: avatar == null
                                      ? null
                                      : DecorationImage(
                                          image: avatar,
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.medium,
                                        ),
                                ),
                                child: _isUploadingPhoto
                                    ? Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(20),
                                          color: const Color.fromRGBO(0, 0, 0, 0.35),
                                        ),
                                        child: const Center(
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
                                        ? const Icon(Icons.person_outline,
                                            size: 40, color: Color(0xFF9E9E9E))
                                        : null),
                              );
                              }),
                            ),
                          ),
                          // Affordance: without it the avatar reads as decoration.
                          Positioned(
                            bottom: -4,
                            right: -4,
                            child: GestureDetector(
                              onTap: _changePhoto,
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9F29),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2.5),
                                ),
                                child: const Icon(Icons.photo_camera_outlined,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _displayName ??
                            FirebaseAuth.instance.currentUser?.displayName ??
                            'User',
                        style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: const Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _memberSinceLabel(),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Section 3 - Preferences
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          "PREFERENCES",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            letterSpacing: 2,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                       Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Column(
                            children: [
                              _buildPreferencesRow(
                                icon: Icons.person_outline,
                                label: 'Account Settings',
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
                                onTap: () async {
                                  // push, not go: this is a subscreen, so back must
                                  // return here rather than exiting the app.
                                  final changed =
                                      await context.push<bool>('/account-settings');
                                  if (changed == true) await _init();
                                },
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.account_balance_outlined,
                                label: 'Monthly Budget',
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color.fromRGBO(255, 159, 41, 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _budgetLimit > 0
                                        ? '฿${_budgetLimit.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}'
                                        : 'Not set',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: const Color(0xFFFF9F29),
                                    ),
                                  ),
                                ),
                                onTap: _showBudgetEditor,
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.event_repeat_outlined,
                                label: 'Subscriptions & Bills',
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
                                // push, not go: a subscreen, so back returns here.
                                onTap: () => context.push<bool>('/subscriptions'),
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.shield_outlined,
                                label: 'Security & Privacy',
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
                                onTap: () => context.push('/security-privacy'),
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.receipt_long_outlined,
                                label: 'Auto-Detect Slips',
                                trailing: Switch(
                                  value: _slipWatcherEnabled,
                                  activeColor: const Color(0xFFFF9F29),
                                  onChanged: (val) async {
                                    setState(() => _slipWatcherEnabled = val);
                                    await GalleryWatcherService()
                                        .setWatcherEnabled(val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Log Out Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GestureDetector(
                    onTap: _showLogoutDialog,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color.fromRGBO(239, 68, 68, 0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout, size: 18, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Text(
                            "Log Out",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: const Color(0xFFEF4444),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),

          // Sticky Header Layers
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: Container(
                  color: const Color.fromRGBO(255, 249, 240, 0.8),
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 48, bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.chevron_left, size: 22, color: Color.fromRGBO(51, 51, 51, 0.7)),
                        ),
                      ),
                      Text(
                        "Profile",
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
          ),

          // Bottom Nav
          const SmartFinBottomNav(currentIndex: 3, showFab: false),
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
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(widget.scaffoldContext).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

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
      await DioClient.dio.put('/api/users/$uid', data: {'budget_limit': amount});

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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Sheet card
          Container(
            margin: const EdgeInsets.only(top: 40),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            ),
            padding: const EdgeInsets.fromLTRB(32, 56, 32, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set Monthly Budget',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Set how much you want to allow yourself to spend each month.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.5,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(height: 8),

                // Amount display with blinking cursor
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '฿ ',
                          style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w800,
                            fontSize: 36,
                            color: const Color(0xFFFF9F29),
                          ),
                        ),
                        Text(
                          _formattedAmount,
                          style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w800,
                            fontSize: 36,
                            color: const Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FadeTransition(
                          opacity: _cursorController,
                          child: Container(
                            width: 2,
                            height: 36,
                            color: const Color(0xFFFF9F29),
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
                        style: const TextStyle(color: Colors.transparent, fontSize: 1),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _isSaving ? null : _saveBudget,
                    child: Container(
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9F29),
                        borderRadius: BorderRadius.circular(9999),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF9F29).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'SAVE BUDGET',
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
                const SizedBox(height: 16),

                // Maybe Later
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'MAYBE LATER',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 2,
                        color: const Color(0xFF9E9E9E),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }
}
