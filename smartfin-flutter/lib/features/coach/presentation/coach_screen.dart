import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/features/coach/data/coach_repository_impl.dart';
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
    final name = prefs.getString('user_name') ??
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
        .map((m) => {
              'role': m['isUser'] == true ? 'user' : 'model',
              'content': m['text'].toString(),
            })
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
            ? (result.data ?? 'Sorry, I had trouble responding 🐾')
            : 'Sorry, I couldn\'t connect. Please try again. 🐾',
      });
    });
    _scrollToBottom();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  /// "TODAY", "YESTERDAY", or "12 SEP 2026" for anything older.
  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    if (_sameDay(date, now)) return 'TODAY';
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'YESTERDAY';
    }
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  double _easeBounce(double x) {
    if (x < 0.5) return 2.0 * x * x;
    return 1.0 - 2.0 * (1.0 - x) * (1.0 - x);
  }

  // ── Widget builders ───────────────────────────────────────────────────────

  Widget _buildRichText(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 1.5,
        color: const Color.fromRGBO(51, 51, 51, 0.9),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CoachAvatar(),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(0),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border:
                Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _typingAnimCtrl,
                builder: (context, child) {
                  final offset = (index * 0.2);
                  final value = (_typingAnimCtrl.value - offset) % 1.0;
                  final sineValue =
                      (value < 0 || value > 0.5) ? 0.0 : (1.0 - (value * 2));
                  return Transform.translate(
                    offset: Offset(0, -5 * _easeBounce(sineValue)),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF9E9E9E),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isUser = msg['isUser'] as bool;
    final tags = (msg['tags'] as List<String>?) ?? [];
    final chips = (msg['chips'] as List<String>?) ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _CoachAvatar(),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: FractionallySizedBox(
              widthFactor: 0.8,
              alignment:
                  isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Chat bubble
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFFFF9F29)
                          : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: isUser
                            ? const Radius.circular(16)
                            : const Radius.circular(0),
                        topRight: isUser
                            ? const Radius.circular(0)
                            : const Radius.circular(16),
                        bottomLeft: const Radius.circular(16),
                        bottomRight: const Radius.circular(16),
                      ),
                      border: isUser
                          ? Border.all(color: const Color(0xFFFF9F29))
                          : Border.all(
                              color:
                                  const Color.fromRGBO(234, 226, 214, 0.4)),
                    ),
                    child: isUser
                        ? Text(
                            msg['text'] as String,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              height: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : _buildRichText(msg['text'] as String),
                  ),

                  // Suggestion chips (welcome message only)
                  if (chips.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: chips
                            .map((chip) => GestureDetector(
                                  onTap: () => _sendMessage(chip),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF9F29)
                                          .withOpacity(0.08),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFFF9F29)
                                              .withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      chip,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: const Color(0xFFFF9F29),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),

                  // Action tags
                  if (tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tags
                            .map((t) => GestureDetector(
                                  onTap: () => ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                          content:
                                              Text('Coming soon'))),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                          color:
                                              const Color(0xFFEAE2D6)),
                                    ),
                                    child: Text(
                                      t,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: const Color(0xFF333333),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),

                  // Timestamp
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      msg['time'] as String,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        color: const Color(0xFF9E9E9E),
                      ),
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
              const SizedBox(height: 124),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 24)
                      .copyWith(bottom: 156),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Typing indicator
                    if (index == _messages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 32),
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
                    final previous =
                        index == 0 ? null : _messages[index - 1]['at'] as DateTime?;
                    if (at == null || (previous != null && _sameDay(at, previous))) {
                      return bubble;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(240, 235, 225, 0.6),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                              child: Text(
                                _dayLabel(at),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 9,
                                  letterSpacing: 1.5,
                                  color: const Color(0xFF9E9E9E),
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
                filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: Container(
                  height: 124,
                  color: const Color.fromRGBO(255, 249, 240, 0.8),
                  padding: const EdgeInsets.only(
                      left: 24, right: 24, top: 48, bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color.fromRGBO(
                                    234, 226, 214, 0.6)),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.chevron_left,
                              size: 22,
                              color: Color.fromRGBO(51, 51, 51, 0.7)),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'AI Coach',
                            style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: const Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
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
              color: const Color(0xFFFFF9F0),
              padding: const EdgeInsets.only(
                  left: 24, right: 24, top: 16, bottom: 104),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color.fromRGBO(234, 226, 214, 0.6)),
                ),
                padding: const EdgeInsets.only(
                    left: 20, right: 6, top: 6, bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        onSubmitted: (value) => _sendMessage(value),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: const Color(0xFF333333),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ask anything...',
                          hintStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color:
                                const Color.fromRGBO(158, 158, 158, 0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () =>
                          _sendMessage(_inputController.text),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF9F29),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_upward,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom nav ─────────────────────────────────────────────────
          const SmartFinBottomNav(currentIndex: 2, showFab: false),
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
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
      ),
      child: Image.asset('assets/images/lucky_cat.png',
          filterQuality: FilterQuality.medium),
    );
  }
}
