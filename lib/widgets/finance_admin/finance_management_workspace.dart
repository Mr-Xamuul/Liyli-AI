import 'package:flutter/material.dart';
import '../../models/finance_models.dart';
import '../../models/user_profile.dart';
import '../../services/finance_storage.dart';
import '../../services/user_auth_service.dart';
import 'manual_payment_dialog.dart';
import 'transaction_receipt_dialog.dart';

/// World-class International Finance & Revenue Management Suite for Leyli AI Admin
class FinanceManagementWorkspace extends StatefulWidget {
  const FinanceManagementWorkspace({super.key});

  @override
  State<FinanceManagementWorkspace> createState() => _FinanceManagementWorkspaceState();
}

class _FinanceManagementWorkspaceState extends State<FinanceManagementWorkspace>
    with SingleTickerProviderStateMixin {
  final _financeStorage = const FinanceStorage();
  final _authService = UserAuthService.instance;

  late TabController _tabController;
  List<PaymentTransaction> _transactions = [];
  List<UserProfile> _students = [];
  FinanceSettings _settings = const FinanceSettings();
  bool _loading = true;

  // Search & Filter state for Transactions Ledger
  String _searchQuery = '';
  String _selectedMethodFilter = 'All';
  String _selectedStatusFilter = 'All';

  // Pricing edit controllers
  late TextEditingController _monthlyPriceCtrl;
  late TextEditingController _yearlyPriceCtrl;
  late TextEditingController _usdToSosCtrl;
  late TextEditingController _evcMerchantCtrl;
  late TextEditingController _zaadMerchantCtrl;
  late TextEditingController _sahalMerchantCtrl;
  late TextEditingController _waafiMerchantCtrl;

  bool _evcEnabled = true;
  bool _zaadEnabled = true;
  bool _sahalEnabled = true;
  bool _waafiEnabled = true;
  bool _stripeEnabled = true;
  bool _paypalEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _monthlyPriceCtrl = TextEditingController();
    _yearlyPriceCtrl = TextEditingController();
    _usdToSosCtrl = TextEditingController();
    _evcMerchantCtrl = TextEditingController();
    _zaadMerchantCtrl = TextEditingController();
    _sahalMerchantCtrl = TextEditingController();
    _waafiMerchantCtrl = TextEditingController();

    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _monthlyPriceCtrl.dispose();
    _yearlyPriceCtrl.dispose();
    _usdToSosCtrl.dispose();
    _evcMerchantCtrl.dispose();
    _zaadMerchantCtrl.dispose();
    _sahalMerchantCtrl.dispose();
    _waafiMerchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final txns = await _financeStorage.getTransactions();
    final settings = await _financeStorage.getSettings();
    final students = await _authService.getAllUsers();

    if (!mounted) return;
    setState(() {
      _transactions = txns;
      _settings = settings;
      _students = students;

      _monthlyPriceCtrl.text = settings.monthlyPrice.toStringAsFixed(2);
      _yearlyPriceCtrl.text = settings.yearlyPrice.toStringAsFixed(2);
      _usdToSosCtrl.text = settings.usdToSosRate.toStringAsFixed(0);
      _evcMerchantCtrl.text = settings.evcMerchantNumber;
      _zaadMerchantCtrl.text = settings.zaadMerchantNumber;
      _sahalMerchantCtrl.text = settings.sahalMerchantNumber;
      _waafiMerchantCtrl.text = settings.waafiMerchantNumber;

      _evcEnabled = settings.evcPlusEnabled;
      _zaadEnabled = settings.zaadEnabled;
      _sahalEnabled = settings.sahalEnabled;
      _waafiEnabled = settings.waafiEnabled;
      _stripeEnabled = settings.stripeEnabled;
      _paypalEnabled = settings.paypalEnabled;

      _loading = false;
    });
  }

  // Financial Metrics calculations
  double get _grossRevenue {
    return _transactions
        .where((t) => t.isCompleted)
        .fold<double>(0.0, (sum, t) => sum + t.amount);
  }

  int get _paidStudentsCount {
    return _students.where((u) => u.isSubscriptionActive).length;
  }

  double get _mrr {
    final activeMonthly = _transactions.where(
      (t) => t.isCompleted && t.planName == 'monthly' && t.createdAt.isAfter(DateTime.now().subtract(const Duration(days: 30))),
    );
    return activeMonthly.fold<double>(0.0, (sum, t) => sum + t.amount);
  }

  double get _arr {
    return (_mrr * 12) + (_transactions.where((t) => t.isCompleted && t.planName == 'yearly').fold<double>(0.0, (sum, t) => sum + t.amount));
  }

  List<PaymentTransaction> get _filteredTransactions {
    return _transactions.where((t) {
      if (_selectedMethodFilter != 'All' && t.paymentMethod != _selectedMethodFilter) {
        return false;
      }
      if (_selectedStatusFilter != 'All' && t.status != _selectedStatusFilter) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchesStudent = t.studentName.toLowerCase().contains(q);
        final matchesEmail = t.studentEmail.toLowerCase().contains(q);
        final matchesId = t.id.toLowerCase().contains(q);
        if (!matchesStudent && !matchesEmail && !matchesId) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _savePricingSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final monthly = double.tryParse(_monthlyPriceCtrl.text.trim()) ?? 5.0;
    final yearly = double.tryParse(_yearlyPriceCtrl.text.trim()) ?? 40.0;
    final rate = double.tryParse(_usdToSosCtrl.text.trim()) ?? 26000.0;

    final updated = _settings.copyWith(
      monthlyPrice: monthly,
      yearlyPrice: yearly,
      usdToSosRate: rate,
      evcPlusEnabled: _evcEnabled,
      evcMerchantNumber: _evcMerchantCtrl.text.trim(),
      zaadEnabled: _zaadEnabled,
      zaadMerchantNumber: _zaadMerchantCtrl.text.trim(),
      sahalEnabled: _sahalEnabled,
      sahalMerchantNumber: _sahalMerchantCtrl.text.trim(),
      waafiEnabled: _waafiEnabled,
      waafiMerchantNumber: _waafiMerchantCtrl.text.trim(),
      stripeEnabled: _stripeEnabled,
      paypalEnabled: _paypalEnabled,
    );

    await _financeStorage.saveSettings(updated);
    setState(() => _settings = updated);

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Dejinta qiimaha & adeegyada lacag-bixinta si guul leh ayaa loo keydiyay!'),
        backgroundColor: Color(0xFF16A34A),
      ),
    );
  }

  Future<void> _showCreateCouponDialog() async {
    final codeCtrl = TextEditingController();
    final discountCtrl = TextEditingController(text: '20');
    final maxUsesCtrl = TextEditingController(text: '100');
    final descCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.local_offer_rounded, color: Color(0xFF0022FF)),
            SizedBox(width: 8),
            Text('Abuur Koodh Cusub (Coupon)'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Koodhka (Tusaale: ARDAY50)',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: discountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Boqolkiiba Qiimo-dhimista (%)',
                  prefixIcon: Icon(Icons.percent_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxUsesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tirada ugu badan ee isticmaali karta',
                  prefixIcon: Icon(Icons.people_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sharaxaad (Faallo)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Jooji'),
          ),
          FilledButton(
            onPressed: () {
              if (codeCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Abuur'),
          ),
        ],
      ),
    );

    if (created == true) {
      final code = codeCtrl.text.trim().toUpperCase();
      final discount = int.tryParse(discountCtrl.text.trim()) ?? 20;
      final maxUses = int.tryParse(maxUsesCtrl.text.trim()) ?? 100;
      final desc = descCtrl.text.trim();

      final coupon = CouponDiscount(
        code: code,
        discountPercent: discount,
        maxUses: maxUses,
        description: desc,
        expiresAt: DateTime.now().add(const Duration(days: 60)),
      );

      await _financeStorage.saveCoupon(coupon);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ==================== Header & Sub-TabBar ====================
        _buildTopHeaderAndTabBar(),
        const SizedBox(height: 16),

        // ==================== Tab Views ====================
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildRevenueOverviewTab(),
              _buildTransactionsLedgerTab(),
              _buildPricingAndGatewaysTab(),
              _buildCouponsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopHeaderAndTabBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFFD97706),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Maamulka Dhaqaalaha & Lacag-bixinta (Finance Suite)',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Dakhliga, Diiwaanka lacagta, Qiimaha & Adeegyada Lacag-bixinta Caalamiga ah',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      ManualPaymentDialog.show(
                        context,
                        students: _students,
                        onPaymentRecorded: _loadData,
                      );
                    },
                    icon: const Icon(Icons.add_card_rounded, size: 16),
                    label: const Text(
                      'Diiwaangeli Lacag-bixin',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0022FF),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Cusbooneysii',
                    onPressed: _loadData,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF0022FF),
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: const Color(0xFF0022FF),
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: 'Guudmarka Dakhliga (Overview)'),
              Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Diiwaanka Lacagta (Ledger)'),
              Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Qorshayaasha & Qiimaha'),
              Tab(icon: Icon(Icons.discount_rounded, size: 18), text: 'Koodhadhka (Coupons)'),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== TAB 1: REVENUE OVERVIEW ====================
  Widget _buildRevenueOverviewTab() {
    final sosAmount = (_grossRevenue * _settings.usdToSosRate) / 1000000;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row of 4 Hero Financial Metric Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Wadarta Dakhliga (Gross)',
                  value: '\$${_grossRevenue.toStringAsFixed(2)}',
                  subtitle: '~${sosAmount.toStringAsFixed(1)}M Somali Shillings',
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF10B981),
                  badgeText: '+18.4% Bishan',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  title: 'MRR (Bille Joogto ah)',
                  value: '\$${_mrr.toStringAsFixed(2)}',
                  subtitle: 'Monthly Recurring Revenue',
                  icon: Icons.autorenew_rounded,
                  color: const Color(0xFF0022FF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  title: 'ARR (Sannadle Run-rate)',
                  value: '\$${_arr.toStringAsFixed(2)}',
                  subtitle: 'Annual Run-rate Forecast',
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  title: 'Ardayda VIP (Paid Tier)',
                  value: '$_paidStudentsCount',
                  subtitle: '${_students.length} Guud ahaan ardayda',
                  icon: Icons.workspace_premium_rounded,
                  color: const Color(0xFFD97706),
                  badgeText: 'VIP Active',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Gateways Breakdown & Plan Breakdown Split
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gateway Breakdown Card
              Expanded(
                flex: 5,
                child: _buildGatewayBreakdownCard(),
              ),
              const SizedBox(width: 16),

              // Plan & Currency Card
              Expanded(
                flex: 4,
                child: _buildPlanAndCurrencyCard(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    String? badgeText,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildGatewayBreakdownCard() {
    final evcTotal = _transactions.where((t) => t.isCompleted && t.paymentMethod.contains('EVC')).fold<double>(0.0, (s, t) => s + t.amount);
    final zaadTotal = _transactions.where((t) => t.isCompleted && t.paymentMethod.contains('Zaad')).fold<double>(0.0, (s, t) => s + t.amount);
    final sahalTotal = _transactions.where((t) => t.isCompleted && t.paymentMethod.contains('Sahal')).fold<double>(0.0, (s, t) => s + t.amount);
    final waafiTotal = _transactions.where((t) => t.isCompleted && t.paymentMethod.contains('Waafi')).fold<double>(0.0, (s, t) => s + t.amount);
    final cardTotal = _transactions.where((t) => t.isCompleted && (t.paymentMethod.contains('Stripe') || t.paymentMethod.contains('Card'))).fold<double>(0.0, (s, t) => s + t.amount);

    final total = _grossRevenue > 0 ? _grossRevenue : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_rounded, size: 18, color: Color(0xFF0022FF)),
              SizedBox(width: 8),
              Text(
                'Dakhliga Adeegyada Lacag-bixinta (Payment Gateways)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildGatewayBar('Hormuud EVC Plus', evcTotal, evcTotal / total, const Color(0xFF16A34A)),
          const SizedBox(height: 12),
          _buildGatewayBar('Telesom Zaad Service', zaadTotal, zaadTotal / total, const Color(0xFF0284C7)),
          const SizedBox(height: 12),
          _buildGatewayBar('Golis Sahal Service', sahalTotal, sahalTotal / total, const Color(0xFFE11D48)),
          const SizedBox(height: 12),
          _buildGatewayBar('Dahabshiil Waafi / e-Dahab', waafiTotal, waafiTotal / total, const Color(0xFFF59E0B)),
          const SizedBox(height: 12),
          _buildGatewayBar('Stripe / Visa & Mastercard', cardTotal, cardTotal / total, const Color(0xFF6366F1)),
        ],
      ),
    );
  }

  Widget _buildGatewayBar(String name, double amount, double fraction, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            Text(
              '\$${amount.toStringAsFixed(2)} (${(fraction * 100).toStringAsFixed(1)}%)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanAndCurrencyCard() {
    final monthlyCount = _transactions.where((t) => t.isCompleted && t.planName == 'monthly').length;
    final yearlyCount = _transactions.where((t) => t.isCompleted && t.planName == 'yearly').length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.currency_exchange_rounded, size: 18, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text(
                'Kala-sarreynta Qorshayaasha & Qiimaha',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bille (\$5 / mo)', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text('$monthlyCount Arday', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0022FF))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sannadle (\$40 / yr)', style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E))),
                      const SizedBox(height: 4),
                      Text('$yearlyCount Arday', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Qiimaha Sarifka (Exchange Rate):',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('1 USD Dollar =', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    Text(
                      '${_settings.usdToSosRate.toStringAsFixed(0)} SOS',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 2: TRANSACTIONS LEDGER ====================
  Widget _buildTransactionsLedgerTab() {
    final filtered = _filteredTransactions;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Bar
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Ka raadi magaca ardayga, email, ama Txn ID...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Gateway Filter
                DropdownButton<String>(
                  value: _selectedMethodFilter,
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('Dhammaan Hababka')),
                    DropdownMenuItem(value: 'EVC Plus', child: Text('EVC Plus')),
                    DropdownMenuItem(value: 'Zaad Service', child: Text('Zaad Service')),
                    DropdownMenuItem(value: 'Sahal', child: Text('Sahal')),
                    DropdownMenuItem(value: 'Waafi', child: Text('Waafi')),
                    DropdownMenuItem(value: 'Stripe Card', child: Text('Stripe Card')),
                    DropdownMenuItem(value: 'Admin Grant', child: Text('Admin Grant')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedMethodFilter = val);
                  },
                ),
                const SizedBox(width: 12),

                // Status Filter
                DropdownButton<String>(
                  value: _selectedStatusFilter,
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('Dhammaan Xaaladaha')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'refunded', child: Text('Refunded')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedStatusFilter = val);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Ledger Table
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('Ma jiraan lacag-bixinno waafaqsan raadintaada.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final txn = filtered[index];
                      return _buildTransactionRow(txn);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(PaymentTransaction txn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: txn.isRefunded ? Colors.red.shade50 : const Color(0xFF0022FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              txn.isRefunded ? Icons.replay_rounded : Icons.check_circle_rounded,
              color: txn.isRefunded ? Colors.red : const Color(0xFF0022FF),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),

          // Student Info & Txn ID
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      txn.studentName,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      txn.id,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                Text(
                  txn.studentEmail,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          // Plan Badge
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: txn.planName == 'yearly' ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                txn.planLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: txn.planName == 'yearly' ? const Color(0xFFB45309) : const Color(0xFF0F172A),
                ),
              ),
            ),
          ),

          // Gateway
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(txn.paymentMethod, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (txn.paymentPhone != null)
                  Text(txn.paymentPhone!, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              ],
            ),
          ),

          // Amount
          Expanded(
            flex: 2,
            child: Text(
              '\$${txn.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: txn.isRefunded ? Colors.grey : const Color(0xFF10B981),
              ),
            ),
          ),

          // Status & Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  TransactionReceiptDialog.show(
                    context,
                    transaction: txn,
                    onRefundRequested: () async {
                      Navigator.pop(context);
                      await _financeStorage.refundTransaction(txn.id, reason: 'Admin Manual Refund');
                      await _loadData();
                    },
                  );
                },
                icon: const Icon(Icons.receipt_rounded, size: 14),
                label: const Text('Rasiid'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (!txn.isRefunded) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.replay_rounded, size: 18, color: Colors.red),
                  tooltip: 'Celi Lacagta (Refund)',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Ma hubtaa inaad lacagta celiso?'),
                        content: Text('Lacagta \$${txn.amount} waxaa loo calaamadinayaa "Refunded" VIP-dana ardayga waa laga qaadayaa.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Maya')),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Haa, Celi'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _financeStorage.refundTransaction(txn.id, reason: 'Admin Direct Refund');
                      await _loadData();
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ==================== TAB 3: PRICING & GATEWAYS ====================
  Widget _buildPricingAndGatewaysTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pricing Form
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.sell_rounded, size: 20, color: Color(0xFF0022FF)),
                    SizedBox(width: 8),
                    Text(
                      'Qiimaha Qorshayaasha VIP-da (Subscription Plans)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _monthlyPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Qiimaha Qorshaha Bille (\$ USD)',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _yearlyPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Qiimaha Qorshaha Sannadle (\$ USD)',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _usdToSosCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '1 USD Sarifka (SOS Shilling)',
                          prefixText: 'SOS ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Payment Gateways Settings
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance_rounded, size: 20, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Text(
                      'Adeegyada Lacag-bixinta (Somali & International Gateways)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildGatewayConfigRow(
                  name: 'Hormuud EVC Plus (Somalia)',
                  enabled: _evcEnabled,
                  onToggle: (v) => setState(() => _evcEnabled = v),
                  controller: _evcMerchantCtrl,
                  hint: '*712*61XXXXXXX*AMOUNT#',
                ),
                const Divider(),
                _buildGatewayConfigRow(
                  name: 'Telesom Zaad Service (Somaliland)',
                  enabled: _zaadEnabled,
                  onToggle: (v) => setState(() => _zaadEnabled = v),
                  controller: _zaadMerchantCtrl,
                  hint: '*220*063XXXXXXX*AMOUNT#',
                ),
                const Divider(),
                _buildGatewayConfigRow(
                  name: 'Golis Sahal Service (Puntland)',
                  enabled: _sahalEnabled,
                  onToggle: (v) => setState(() => _sahalEnabled = v),
                  controller: _sahalMerchantCtrl,
                  hint: '*888*064XXXXXXX*AMOUNT#',
                ),
                const Divider(),
                _buildGatewayConfigRow(
                  name: 'Dahabshiil Waafi / e-Dahab',
                  enabled: _waafiEnabled,
                  onToggle: (v) => setState(() => _waafiEnabled = v),
                  controller: _waafiMerchantCtrl,
                  hint: 'MERCHANT_ID_WAAFI',
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Stripe (Visa & Mastercard International)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  subtitle: const Text('U ogolow ardayda caalamka inay kaarka Visa ama Mastercard ku bixiyaan lacagta'),
                  value: _stripeEnabled,
                  activeThumbColor: const Color(0xFF0022FF),
                  onChanged: (v) => setState(() => _stripeEnabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Save Button
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _savePricingSettings,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Keydi Isbeddelada Dhaqaalaha', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0022FF),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGatewayConfigRow({
    required String name,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required TextEditingController controller,
    required String hint,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            value: enabled,
            activeThumbColor: const Color(0xFF0022FF),
            onChanged: onToggle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controller,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: 'Merchant / Nambarka',
              hintText: hint,
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== TAB 4: COUPONS & DISCOUNTS ====================
  Widget _buildCouponsTab() {
    final coupons = _settings.coupons;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.discount_rounded, color: Color(0xFF0022FF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Koodhadhka Qiimo-dhimista (Active Coupons)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: _showCreateCouponDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Abuur Coupon Cusub'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0022FF),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: coupons.isEmpty
                ? const Center(child: Text('Ma jiraan koodhadh firfircoon hadda.'))
                : ListView.separated(
                    itemCount: coupons.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final c = coupons[index];
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.local_offer_rounded, color: Color(0xFFD97706), size: 20),
                        ),
                        title: Row(
                          children: [
                            Text(
                              c.code,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${c.discountPercent}% OFF',
                                style: const TextStyle(color: Color(0xFF16A34A), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${c.description ?? ''} • ${c.usedCount}/${c.maxUses} la isticmaalay',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: c.isActive,
                              activeThumbColor: const Color(0xFF0022FF),
                              onChanged: (_) async {
                                await _financeStorage.toggleCoupon(c.code);
                                await _loadData();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              onPressed: () async {
                                await _financeStorage.deleteCoupon(c.code);
                                await _loadData();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
