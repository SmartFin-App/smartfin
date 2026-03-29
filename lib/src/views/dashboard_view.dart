import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:smart_fin/src/utils/app_theme.dart';

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartFin'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const FaIcon(FontAwesomeIcons.solidBell, size: 20),
          ),
          IconButton(
            onPressed: () {},
            icon: const FaIcon(FontAwesomeIcons.circleUser, size: 20),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, Alex!',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Your financial health is looking good today.',
              style: Theme.of(context).textTheme.bodyMedium,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: AppTheme.accentGold,
        child: const Icon(Icons.add, color: AppTheme.primaryNavy),
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
            color: AppTheme.primaryNavy,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SummaryCard(
            title: 'Savings',
            amount: '\$4,200',
            icon: FontAwesomeIcons.piggyBank,
            color: Colors.green.shade800,
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
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spending Overview', style: Theme.of(context).textTheme.titleLarge),
              const Icon(Icons.more_horiz, color: AppTheme.textGray),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 200,
            alignment: Alignment.center,
            child: const Text(
              'Chart Placeholder (fl_chart)',
              style: TextStyle(color: AppTheme.textGray),
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
            Text('Recent Transactions', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () {},
              child: const Text('See All', style: TextStyle(color: AppTheme.accentGold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TransactionTile(
          title: 'Starbucks Coffee',
          subtitle: 'Food & Drink • Today',
          amount: '-\$5.50',
          icon: FontAwesomeIcons.mugHot,
        ),
        _TransactionTile(
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
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, color: color, size: 24),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: AppTheme.textGray, fontSize: 14)),
          const SizedBox(height: 4),
          Text(amount, style: const TextStyle(color: AppTheme.textLight, fontSize: 22, fontWeight: FontWeight.bold)),
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
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: FaIcon(icon, color: AppTheme.primaryNavy, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              color: amount.startsWith('-') ? Colors.redAccent : Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
