import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/coach/data/coach_repository_impl.dart';
import 'package:smart_fin/widgets/page_title_row.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  late AnimationController _typingAnimCtrl;
  String _userName = 'there';
  List<Map<String, dynamic>> _messages = [];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _typingAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadUserAndWelcome();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _typingAnimCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadUserAndWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    final name =
        prefs.getString('user_name') ??
        FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ??
        'there';
    if (!mounted) return;
    setState(() => _userName = name);

    // Restore the stored transcript first: switching tabs disposes this screen,
    // so without this the conversation — and the coach's own context, which is
    // built from these messages — resets every time the user leaves.
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      final res = await CoachRepositoryImpl().getHistory(userID: uid);
      if (!mounted) return;
      if (res.success && (res.data?.isNotEmpty ?? false)) {
        setState(() {
          _messages = res.data!.map((m) {
            final created = DateTime.tryParse(m['created_at'] as String? ?? '');
            final at = created?.toLocal() ?? DateTime.now();
            return <String, dynamic>{
              'isUser': m['role'] == 'user',
              'at': at,
              'time': _formatTime(at),
              'text': m['content'] as String? ?? '',
              'actions': CoachAction.listFrom(m['actions']),
            };
          }).toList();
        });
        _scrollToBottom();
        return;
      }
    }

    // No stored conversation yet — greet instead.
    setState(() {
      _messages.add({
        'isUser': false,
        'at': DateTime.now(),
        'time': _formatTime(DateTime.now()),
        'text':
            'Hi $_userName! 🐾 I\'m Kwak, your AI Coach. Ask me anything about your spending!',
        'chips': [
          'How much did I spend this month?',
          'Am I on budget?',
          'Where can I save money?',
        ],
      });
    });
  }

  // ── Messaging ────────────────────────────────────────────────────────────

  Future<void> _sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Remove suggestion chips from welcome message on first send
    if (_messages.isNotEmpty && _messages[0]['chips'] != null) {
      setState(() => _messages[0].remove('chips'));
    }

    // Build history (exclude the message we're about to add)
    final history = _messages
        .where((m) => m['text'] != null && m['text'].toString().isNotEmpty)
        .where((m) => m['text'] != userMessage)
        .map(
          (m) => {
            'role': m['isUser'] == true ? 'user' : 'model',
            'content': m['text'].toString(),
          },
        )
        .toList();

    setState(() {
      _messages.add({
        'isUser': true,
        'at': DateTime.now(),
        'time': _formatTime(DateTime.now()),
        'text': userMessage,
      });
      _inputController.clear();
      _isTyping = true;
    });

    _scrollToBottom();

    final result = await CoachRepositoryImpl().askCoach(
      userID: uid,
      message: userMessage,
      history: history,
    );

    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add({
        'isUser': false,
        'at': DateTime.now(),
        'time': _formatTime(DateTime.now()),
        'text': result.success
            ? (result.data?.text ?? 'Sorry, I had trouble responding 🐾')
            : 'Sorry, I couldn\'t connect. Please try again. 🐾',
        'actions': result.data?.actions ?? const <CoachAction>[],
      });
    });
    _scrollToBottom();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// A chip for one write the coach made. Tapping it opens what changed: the
  /// new transaction, or Profile for the budget.
  Widget _buildActionChip(CoachAction a) {
    final isExpense = a.action == 'add_transaction';
    final VoidCallback? onTap = isExpense
        ? (a.id == null ? null : () => context.push('/transaction/${a.id}'))
        : a.action == 'update_budget_limit'
        ? () => context.push('/profile')
        : null;

    return AppChip(
      label: a.label,
      icon: isExpense
          ? Icons.receipt_long_outlined
          : Icons.account_balance_wallet_outlined,
      onTap: onTap,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime date) {
    int h = date.hour;
    int m = date.minute;
    String period = h >= 12 ? 'PM' : 'AM';
    h = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    String ms = m < 10 ? '0$m' : '$m';
    return '$h:$ms $period';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Today", "Yesterday", or "12 Sep 2026" for anything older.
  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    if (_sameDay(date, now)) return 'Today';
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  double _easeBounce(double x) {
    if (x < 0.5) return 2.0 * x * x;
    return 1.0 - 2.0 * (1.0 - x) * (1.0 - x);
  }

  // ── Widget builders ───────────────────────────────────────────────────────

  static const _bubbleRadius = Radius.circular(AppRadius.lg);
  // The corner nearest the speaker is tighter, which reads as a speech tail.
  static const _tailRadius = Radius.circular(6);

  static BoxDecoration _bubble({required bool isUser}) => BoxDecoration(
    color: isUser ? AppColors.primary.withValues(alpha: 0.16) : AppColors.white,
    borderRadius: BorderRadius.only(
      topLeft: isUser ? _bubbleRadius : _tailRadius,
      topRight: isUser ? _tailRadius : _bubbleRadius,
      bottomLeft: _bubbleRadius,
      bottomRight: _bubbleRadius,
    ),
    border: isUser
        ? null
        : Border.all(color: AppColors.border.withValues(alpha: 0.7)),
    boxShadow: isUser ? null : AppShadows.card,
  );

  /// Renders the little Markdown the coach writes: `**bold**` and bullet
  /// lines starting with `*` or `-`. Shown raw, the asterisks read as noise.
  Widget _buildRichText(String text) {
    final lines = text.trim().split('\n');
    final children = <Widget>[];
    for (final raw in lines) {
      final bullet = RegExp(r'^\s*[*-]\s+').firstMatch(raw);
      final line = bullet == null ? raw : raw.substring(bullet.end);
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
        continue;
      }
      final spans = _boldSpans(line);
      children.add(
        bullet == null
            ? Text.rich(TextSpan(children: spans), style: AppTextStyles.body)
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•  ',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.primaryText,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: spans),
                        style: AppTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Splits a line on `**`: every odd piece was inside a pair, so it is bold.
  /// An unpaired `**` stays as written.
  static List<InlineSpan> _boldSpans(String line) {
    final parts = line.split('**');
    if (parts.length.isEven) return [TextSpan(text: line)];
    return [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(
            text: parts[i],
            style: i.isOdd
                ? const TextStyle(fontWeight: FontWeight.w600)
                : null,
          ),
    ];
  }

  Widget _buildTypingIndicator() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CoachAvatar(),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: _bubble(isUser: false),
          child: Semantics(
            label: 'AI Coach is typing',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _typingAnimCtrl,
                  builder: (context, child) {
                    final offset = (index * 0.2);
                    final value = (_typingAnimCtrl.value - offset) % 1.0;
                    final sineValue = (value < 0 || value > 0.5)
                        ? 0.0
                        : (1.0 - (value * 2));
                    return Transform.translate(
                      offset: Offset(0, -5 * _easeBounce(sineValue)),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isUser = msg['isUser'] as bool;
    final chips = (msg['chips'] as List<String>?) ?? [];
    final actions = (msg['actions'] as List<CoachAction>?) ?? const [];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _CoachAvatar(),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: FractionallySizedBox(
              widthFactor: isUser ? 0.8 : 0.9,
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Chat bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: _bubble(isUser: isUser),
                    child: isUser
                        ? Text(msg['text'] as String, style: AppTextStyles.body)
                        : _buildRichText(msg['text'] as String),
                  ),

                  // Suggestion chips (welcome message only)
                  if (chips.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: chips
                            .map(
                              (chip) => AppChip(
                                label: chip,
                                onTap: () => _sendMessage(chip),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  // What the coach changed while answering
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: actions.map(_buildActionChip).toList(),
                      ),
                    ),

                  // Timestamp
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs + 2,
                      left: 4,
                      right: 4,
                    ),
                    child: Text(
                      msg['time'] as String,
                      style: AppTextStyles.caption.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // ── Chat list ──────────────────────────────────────────────────
          Column(
            children: [
              // Header content ends at 48 + 40, plus 8 below it.
              const SizedBox(height: 96),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.lg,
                    AppSpacing.screen,
                    172,
                  ),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Typing indicator
                    if (index == _messages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: _buildTypingIndicator(),
                      );
                    }

                    final message = _messages[index];
                    final bubble = _buildMessage(message);

                    // A separator goes above the first message of each day. The
                    // transcript is restored from the server and can span weeks,
                    // so a single pill at the top once labelled every old message
                    // "TODAY".
                    final at = message['at'] as DateTime?;
                    final previous = index == 0
                        ? null
                        : _messages[index - 1]['at'] as DateTime?;
                    if (at == null ||
                        (previous != null && _sameDay(at, previous))) {
                      return bubble;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                _dayLabel(at),
                                style: AppTextStyles.label.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        bubble,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),

          // ── Sticky header ──────────────────────────────────────────────
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
                  child: const PageTitleRow(title: 'AI Coach'),
                ),
              ),
            ),
          ),

          // ── Input bar ──────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              // Fades the chat out under the input instead of cutting it.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.cream.withValues(alpha: 0),
                    AppColors.cream,
                  ],
                  stops: const [0, 0.25],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.xl,
                AppSpacing.screen,
                108,
              ),
              child: TextField(
                controller: _inputController,
                onSubmitted: (value) => _sendMessage(value),
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Ask about your spending',
                  contentPadding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(6),
                    child: IconButton.filled(
                      onPressed: () => _sendMessage(_inputController.text),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                      ),
                      icon: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 20,
                        semanticLabel: 'Send',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom nav ─────────────────────────────────────────────────
          const SmartFinBottomNav(currentIndex: 2),
        ],
      ),
    );
  }
}

/// The coach's mascot. The lucky cat is the coach's face throughout the app —
/// the rest of the interface uses the SmartFin wordmark instead.
class _CoachAvatar extends StatelessWidget {
  const _CoachAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Image.asset(
        'assets/images/lucky_cat.png',
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
