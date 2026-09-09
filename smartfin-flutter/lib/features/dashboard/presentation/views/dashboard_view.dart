import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/constants/text_style.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text('SmartFin', style: AppTextStyles.screenTitle),
        backgroundColor: AppColors.cream,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const FaIcon(FontAwesomeIcons.solidBell, size: 20, color: AppColors.textDark),
          ),
          IconButton(
            onPressed: () {},
            icon: const FaIcon(FontAwesomeIcons.circleUser, size: 20, color: AppColors.textDark),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 150, // Added padding to clear the floating nav bar
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, Alex!',
              style: AppTextStyles.displayLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Your financial health is looking good today.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 30),
            _buildSummaryCards(context),
            const SizedBox(height: 30),
            _buildChartSection(context),
            const SizedBox(height: 30),
            _buildRecentTransactions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'Balance',
            amount: '\$12,450',
            icon: FontAwesomeIcons.wallet,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SummaryCard(
            title: 'Savings',
            amount: '\$4,200',
            icon: FontAwesomeIcons.piggyBank,
            color: AppColors.income,
          ),
        ),
      ],
    );
  }

  Widget _buildChartSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spending Overview', style: AppTextStyles.displayMedium.copyWith(fontSize: 20)),
              const Icon(Icons.more_horiz, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 200,
            alignment: Alignment.center,
            child: Text(
              'Chart Placeholder (fl_chart)',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Transactions', style: AppTextStyles.screenTitle),
            TextButton(
              onPressed: () {},
              child: Text('See All', style: AppTextStyles.bodyBold.copyWith(color: AppColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _TransactionTile(
          title: 'Starbucks Coffee',
          subtitle: 'Food & Drink • Today',
          amount: '-\$5.50',
          icon: FontAwesomeIcons.mugHot,
        ),
        const _TransactionTile(
          title: 'Rent Payment',
          subtitle: 'Housing • Yesterday',
          amount: '-\$1,200.00',
          icon: FontAwesomeIcons.house,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, color: color, size: 24),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.label.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(amount, style: AppTextStyles.greeting.copyWith(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final IconData icon;

  const _TransactionTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: FaIcon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.transactionName),
                Text(subtitle, style: AppTextStyles.transactionMeta.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(
            amount,
            style: AppTextStyles.bodyBold.copyWith(
              color: amount.startsWith('-') ? Colors.redAccent : AppColors.income,
            ),
          ),
        ],
      ),
    );
  }
}
