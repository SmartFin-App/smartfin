import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';

class ManualAddScreen extends StatefulWidget {
  final String? type;

  const ManualAddScreen({super.key, this.type});

  @override
  State<ManualAddScreen> createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen> with TickerProviderStateMixin {
  late bool _isExpense;
  String? _selectedCategory;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _merchantController = TextEditingController();
  final FocusNode _merchantFocus = FocusNode();
  bool _merchantIsFocused = false;
  bool _isSavePressed = false;
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  // Animations
  late AnimationController _amountAnimController;
  late Animation<double> _amountScale;
  late Animation<double> _amountFade;
  
  late AnimationController _gridAnimController;
  late Animation<Offset> _gridSlide;
  late Animation<double> _gridFade;

  @override
  void initState() {
    super.initState();
    _isExpense = widget.type != 'income';
    
    _merchantFocus.addListener(() {
      setState(() {
        _merchantIsFocused = _merchantFocus.hasFocus;
      });
    });

    // Amount Load Animation
    _amountAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _amountScale = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _amountAnimController, curve: Curves.easeOutBack));
    _amountFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _amountAnimController, curve: Curves.easeOut));
    
    _amountAnimController.forward();

    // Grid Slide Animation
    _gridAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _gridSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
        CurvedAnimation(parent: _gridAnimController, curve: Curves.easeOutCubic));
    _gridFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _gridAnimController, curve: Curves.easeOut));
        
    Future.delayed(const Duration(milliseconds: 100), () => _gridAnimController.forward());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _merchantFocus.dispose();
    _amountAnimController.dispose();
    _gridAnimController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) return "Today";
    if (checkDate == yesterday) return "Yesterday";
    return DateFormat('MMM d, yyyy').format(date);
  }

  Future<void> _saveTransaction() async {
    final amountText = _amountController.text.trim().replaceAll(',', '');
    final amount = int.tryParse(amountText) ?? (double.tryParse(amountText)?.toInt());

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an amount")),
      );
      return;
    }

    if (_merchantController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a source or merchant")),
      );
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a category")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final result = await TransactionRepositoryImpl().createTransaction(
        userID: uid,
        merchant: _merchantController.text.trim(),
        amount: amount,
        type: _isExpense ? 'expense' : 'income',
        category: _selectedCategory!,
        source: 'manual',
        date: _selectedDate,
      );

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Transaction saved! 🐾")),
        );
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Failed to save transaction.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  final List<Map<String, dynamic>> _expenseCats = [
    {'label': 'Food', 'icon': Icons.restaurant_outlined, 'color': const Color(0xFFFF9F29)},
    {'label': 'Transport', 'icon': Icons.directions_car_outlined, 'color': const Color(0xFF4A90E2)},
    {'label': 'Entertainment', 'icon': Icons.movie_outlined, 'color': const Color(0xFF9C27B0)},
    {'label': 'Shopping', 'icon': Icons.shopping_bag_outlined, 'color': const Color(0xFFE91E63)},
    {'label': 'Health', 'icon': Icons.favorite_outline, 'color': const Color(0xFFEF4444)},
    {'label': 'Groceries', 'icon': Icons.local_grocery_store_outlined, 'color': const Color(0xFF4CAF50)},
    {'label': 'Bills', 'icon': Icons.receipt_outlined, 'color': const Color(0xFFFF9800)},
    {'label': 'Other', 'icon': Icons.add_circle_outline, 'color': const Color(0xFF9E9E9E)},
  ];

  final List<Map<String, dynamic>> _incomeCats = [
    {'label': 'Salary', 'icon': Icons.account_balance_wallet_outlined, 'color': const Color(0xFFFF9F29)},
    {'label': 'Gifts', 'icon': Icons.card_giftcard_outlined, 'color': const Color(0xFF4A90E2)},
    {'label': 'Refunds', 'icon': Icons.local_offer_outlined, 'color': const Color(0xFF4CAF50)},
    {'label': 'Other', 'icon': Icons.add_circle_outline, 'color': const Color(0xFF9E9E9E)},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F0),
      body: Stack(
        children: [
          // Main Scrollable Area
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 104, bottom: 120),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // Toggle Expense / Income
                Center(
                  child: Container(
                    width: 260,
                    margin: const EdgeInsets.only(bottom: 48),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(240, 235, 225, 0.3),
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.2)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!_isExpense) {
                                setState(() {
                                  _isExpense = true;
                                  _selectedCategory = null;
                                  _gridAnimController.forward(from: 0);
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _isExpense ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(9999),
                                boxShadow: _isExpense ? [
                                  const BoxShadow(
                                    color: Color.fromRGBO(0, 0, 0, 0.05),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  )
                                ] : [],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "EXPENSE",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                  letterSpacing: 2.0,
                                  color: _isExpense ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_isExpense) {
                                setState(() {
                                  _isExpense = false;
                                  _selectedCategory = null;
                                  _gridAnimController.forward(from: 0);
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_isExpense ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(9999),
                                boxShadow: !_isExpense ? [
                                  const BoxShadow(
                                    color: Color.fromRGBO(0, 0, 0, 0.05),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  )
                                ] : [],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "INCOME",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                  letterSpacing: 2.0,
                                  color: !_isExpense ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Amount Input
                FadeTransition(
                  opacity: _amountFade,
                  child: ScaleTransition(
                    scale: _amountScale,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 48),
                      child: Column(
                        children: [
                          Text(
                            "Transaction Amount",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 2,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "฿",
                                style: GoogleFonts.bricolageGrotesque(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 36,
                                  color: const Color(0xFFFF9F29),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 224,
                                child: TextField(
                                  controller: _amountController,
                                  autofocus: true,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.bricolageGrotesque(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 60,
                                    letterSpacing: -2.0,
                                    color: const Color(0xFF333333),
                                    height: 1.1,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: "0",
                                    hintStyle: GoogleFonts.bricolageGrotesque(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 60,
                                      color: const Color.fromRGBO(51, 51, 51, 0.1),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),

                // Source / Merchant
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Source / Merchant",
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 2,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 40),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _merchantIsFocused ? const Color(0xFFFF9F29) : const Color(0xFFEAE2D6),
                            width: _merchantIsFocused ? 2 : 1,
                          ),
                          boxShadow: _merchantIsFocused ? [
                            const BoxShadow(
                              color: Color.fromRGBO(255, 159, 41, 0.05),
                              blurRadius: 10,
                              spreadRadius: 4,
                            )
                          ] : [],
                        ),
                        child: TextField(
                          controller: _merchantController,
                          focusNode: _merchantFocus,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: const Color(0xFF333333),
                          ),
                          decoration: InputDecoration(
                            hintText: "Where did it come from?",
                            hintStyle: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: const Color.fromRGBO(158, 158, 158, 0.3),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Date Picker
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Date",
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 2,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: Color(0xFFFF9F29),
                                    onPrimary: Colors.white,
                                    surface: Color(0xFFFFF9F0),
                                    onSurface: Color(0xFF333333),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          margin: const EdgeInsets.only(bottom: 40),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEAE2D6)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: Color(0xFF9E9E9E),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatDate(_selectedDate),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  color: const Color(0xFF333333),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Categories Grid
                FadeTransition(
                  opacity: _gridFade,
                  child: SlideTransition(
                    position: _gridSlide,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Category",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 2,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 2.4, // Width vs height tuning
                            ),
                            itemCount: _isExpense ? _expenseCats.length : _incomeCats.length,
                            itemBuilder: (context, index) {
                              final cat = _isExpense ? _expenseCats[index] : _incomeCats[index];
                              final isSelected = _selectedCategory == cat['label'];
                              
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedCategory = cat['label'] as String;
                                  });
                                },
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 1.0, end: isSelected ? 0.98 : 1.0),
                                  duration: const Duration(milliseconds: 100),
                                  builder: (context, scale, child) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        alignment: Alignment.centerLeft,
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color.fromRGBO(255, 159, 41, 0.05) : Colors.white,
                                          borderRadius: BorderRadius.circular(32),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFFEAE2D6),
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color.fromRGBO(0, 0, 0, 0.02),
                                              blurRadius: 8,
                                              offset: Offset(0, 4),
                                            )
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: (cat['color'] as Color).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: Icon(
                                                cat['icon'] as IconData,
                                                color: cat['color'] as Color,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                (cat['label'] as String).toUpperCase(),
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                  letterSpacing: 1.5,
                                                  color: const Color(0xFF333333),
                                                  height: 1.0,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Sticky Top Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  color: const Color.fromRGBO(255, 249, 240, 0.8),
                  padding: const EdgeInsets.only(top: 48, bottom: 24, left: 24, right: 24),
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
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color.fromRGBO(234, 226, 214, 0.5),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              )
                            ],
                          ),
                          child: const Icon(Icons.chevron_left, color: Color.fromRGBO(51, 51, 51, 0.7), size: 22),
                        ),
                      ),
                      Text(
                        "Add Transaction",
                        style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.5,
                          color: const Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(width: 40), // spacer completely bounds perfectly
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Fixed Bottom Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFFFFF9F0)],
                ),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32, left: 32, right: 32),
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _isSavePressed = true),
                    onTapUp: (_) {
                      setState(() => _isSavePressed = false);
                      _saveTransaction();
                    },
                    onTapCancel: () => setState(() => _isSavePressed = false),
                    child: AnimatedScale(
                      scale: _isSavePressed ? 0.98 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F29),
                          borderRadius: BorderRadius.circular(9999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(255, 159, 41, 0.4),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            )
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                "SAVE TRANSACTION",
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
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
