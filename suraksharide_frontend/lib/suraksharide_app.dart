import 'dart:math';

import 'package:flutter/material.dart';

enum UserRole { rider, admin }
enum PlanId { s, m, l }
enum Severity { low, medium, high }

extension on PlanId {
  String get name {
    switch (this) {
      case PlanId.s:
        return 'S';
      case PlanId.m:
        return 'M';
      case PlanId.l:
        return 'L';
    }
  }

  int get weeklyCoverage {
    switch (this) {
      case PlanId.s:
        return 2000;
      case PlanId.m:
        return 3500;
      case PlanId.l:
        return 5000;
    }
  }

  /// Mock base premium because the README provides the formula but not base values.
  double get basePremium {
    switch (this) {
      case PlanId.s:
        return 500;
      case PlanId.m:
        return 875;
      case PlanId.l:
        return 1250;
    }
  }

  Color get accent {
    switch (this) {
      case PlanId.s:
        return const Color(0xFF2E86AB);
      case PlanId.m:
        return const Color(0xFFF18F01);
      case PlanId.l:
        return const Color(0xFF7B2CBF);
    }
  }
}

class AuthUser {
  final String email;
  final UserRole role;
  const AuthUser({required this.email, required this.role});
}

class RiskAlert {
  final String id;
  final String title;
  final String triggerDescription;
  final Severity severity;
  final DateTime createdAt;

  const RiskAlert({
    required this.id,
    required this.title,
    required this.triggerDescription,
    required this.severity,
    required this.createdAt,
  });
}

class Payout {
  final String id;
  final String reason;
  final DateTime date;
  final double amount;

  const Payout({
    required this.id,
    required this.reason,
    required this.date,
    required this.amount,
  });
}

class FraudFlag {
  final String id;
  final String riderEmail;
  final double score; // 0..1
  final List<String> reasons;
  final DateTime createdAt;

  const FraudFlag({
    required this.id,
    required this.riderEmail,
    required this.score,
    required this.reasons,
    required this.createdAt,
  });
}

double _severityToRisk(Severity s) {
  switch (s) {
    case Severity.low:
      return 0.15;
    case Severity.medium:
      return 0.45;
    case Severity.high:
      return 0.8;
  }
}

double _clamp01(double v) => v.clamp(0.0, 1.0);

int _hashToInt(String s) {
  // Deterministic, lightweight hash for mock data.
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

double _seededDouble(String seed) {
  final h = _hashToInt(seed);
  return (h % 1000) / 1000.0; // 0..0.999
}

String inrInt(int v) => '₹${v.toString()}';
String inrAmt(double v) => '₹${v.toStringAsFixed(0)}';

String formatDate(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

double computeWeeklyPremium({
  required PlanId planId,
  required double riskScore01,
}) {
  // README: Weekly Premium = Base Premium × (1 + 0.5 × Risk Score)
  final base = planId.basePremium;
  return base * (1 + 0.5 * riskScore01);
}

double computePotentialPayout({
  required PlanId planId,
  required RiskAlert alert,
}) {
  // README: Loss = max(0, E − A); Payout = Loss within weekly cap.
  //
  // Prototype note: since there is no backend earnings series yet, we simulate:
  // - Expected earnings (E) as a fraction of weekly coverage cap.
  // - Actual earnings (A) decreases more for higher severity.
  final cap = planId.weeklyCoverage.toDouble();

  final expectedFactor = 0.55 + (_seededDouble('${planId.name}:${alert.id}:E') * 0.15); // 0.55..0.7
  final lossSeverity = 0.18 + (_severityToRisk(alert.severity) * 0.5);

  final expectedEarnings = cap * expectedFactor;
  final actualEarnings = max(0.0, expectedEarnings * (1 - lossSeverity));

  final loss = max(0.0, expectedEarnings - actualEarnings);
  return min(cap, loss);
}

double predictedRiskScoreForPlan(PlanId planId) {
  // Mock "AI-generated risk score (0–1)".
  final base = switch (planId) {
    PlanId.s => 0.22,
    PlanId.m => 0.38,
    PlanId.l => 0.55,
  };
  final jitter = (_seededDouble('risk:${planId.name}') - 0.5) * 0.08; // +/-0.04
  return _clamp01(base + jitter);
}

class SurakshaRideApp extends StatefulWidget {
  const SurakshaRideApp({super.key});

  @override
  State<SurakshaRideApp> createState() => _SurakshaRideAppState();
}

class _SurakshaRideAppState extends State<SurakshaRideApp> {
  AuthUser? _user;
  PlanId _planId = PlanId.s;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0B7285);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SurakshaRide',
      theme: ThemeData(
        useMaterial3: false,
        colorScheme: ColorScheme.fromSeed(seedColor: accent),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: _user == null
          ? LoginPage(
              onLogin: (u) => setState(() => _user = u),
            )
          : (_user!.role == UserRole.rider
              ? RiderHome(
                  user: _user!,
                  planId: _planId,
                  onPlanChanged: (newPlan) => setState(() => _planId = newPlan),
                  onSignOut: () => setState(() => _user = null),
                )
              : AdminHome(
                  user: _user!,
                  onSignOut: () => setState(() => _user = null),
                  planIdHint: _planId,
                )),
    );
  }
}

class LoginPage extends StatefulWidget {
  final void Function(AuthUser user) onLogin;
  const LoginPage({super.key, required this.onLogin});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController(text: 'rider@demo.com');
  final _passCtrl = TextEditingController(text: 'demo123');

  UserRole _role = UserRole.rider;
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _attemptLogin() {
    setState(() => _error = null);

    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;

    final ok = switch (_role) {
      UserRole.rider => (email == 'rider@demo.com' && pass == 'demo123'),
      UserRole.admin => (email == 'admin@demo.com' && pass == 'demo123'),
    };

    if (!ok) {
      setState(() => _error = 'Invalid demo credentials for $_role. Try demo123.');
      return;
    }

    widget.onLogin(AuthUser(email: email, role: _role));
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0B7285);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SurakshaRide'),
        backgroundColor: accent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(child: _LeftHero()),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Login',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          _RoleSelector(
                            role: _role,
                            onChanged: (r) => setState(() => _role = r),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passCtrl,
                            obscureText: !_showPass,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                            ),
                          ],
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: _attemptLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Continue'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () {
                              if (_role == UserRole.rider) {
                                setState(() {
                                  _emailCtrl.text = 'rider@demo.com';
                                  _passCtrl.text = 'demo123';
                                });
                              } else {
                                setState(() {
                                  _emailCtrl.text = 'admin@demo.com';
                                  _passCtrl.text = 'demo123';
                                });
                              }
                            },
                            child: const Text('Fill Demo Credentials'),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Prototype UI: data are mocked (no backend yet).',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI-powered, weekly parametric income protection',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Auto-triggers payouts using external signals (weather, AQI, and simulated platform outage). No claims workflow for riders.',
              style: TextStyle(color: Colors.black.withOpacity(0.7), height: 1.3),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroChip(icon: Icons.auto_awesome_outlined, text: 'AI risk pricing'),
                _HeroChip(icon: Icons.auto_fix_high_outlined, text: 'Zero-claims payouts'),
                _HeroChip(icon: Icons.wallet_travel_outlined, text: 'Protection wallet'),
                _HeroChip(icon: Icons.shield_outlined, text: 'Fraud detection (prototype)'),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withOpacity(0.25)),
                color: cs.primary.withOpacity(0.06),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly plans', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('S: ₹2,000 weekly coverage'),
                  Text('M: ₹3,500 weekly coverage'),
                  Text('L: ₹5,000 weekly coverage'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeroChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(text),
      avatar: Icon(icon, size: 18, color: cs.primary),
      backgroundColor: cs.primary.withOpacity(0.07),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final UserRole role;
  final ValueChanged<UserRole> onChanged;
  const _RoleSelector({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Login as', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ToggleButtons(
          isSelected: [role == UserRole.rider, role == UserRole.admin],
          onPressed: (idx) => onChanged(idx == 0 ? UserRole.rider : UserRole.admin),
          borderRadius: BorderRadius.circular(12),
          selectedColor: Colors.white,
          fillColor: Theme.of(context).colorScheme.primary,
          constraints: const BoxConstraints(minWidth: 120, minHeight: 42),
          children: const [
            Row(children: [Icon(Icons.directions_bike), SizedBox(width: 6), Text('Rider')]),
            Row(children: [Icon(Icons.admin_panel_settings), SizedBox(width: 6), Text('Admin')]),
          ],
        ),
      ],
    );
  }
}

class RiderHome extends StatefulWidget {
  final AuthUser user;
  final PlanId planId;
  final ValueChanged<PlanId> onPlanChanged;
  final VoidCallback onSignOut;

  const RiderHome({
    super.key,
    required this.user,
    required this.planId,
    required this.onPlanChanged,
    required this.onSignOut,
  });

  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  int _tabIndex = 0;
  late PlanId _selectedPlanId;

  double _walletBalance = 1200;
  final List<Payout> _payouts = [];
  final Set<String> _simulatedAlertIds = {};
  late List<RiskAlert> _alerts;

  @override
  void initState() {
    super.initState();
    _selectedPlanId = widget.planId;
    _alerts = _buildAlertsForDemo(widget.planId);
  }

  @override
  void didUpdateWidget(covariant RiderHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.planId != widget.planId) {
      _selectedPlanId = widget.planId;
      _alerts = _buildAlertsForDemo(widget.planId);
    }
  }

  List<RiskAlert> _buildAlertsForDemo(PlanId planId) {
    final now = DateTime.now();
    return [
      RiskAlert(
        id: 'rain',
        title: 'Rainfall spike',
        triggerDescription: 'Rainfall >= 50 mm in 24 hours',
        severity: planId == PlanId.s ? Severity.medium : Severity.high,
        createdAt: now.subtract(const Duration(hours: 11)),
      ),
      RiskAlert(
        id: 'temp',
        title: 'Extreme heat',
        triggerDescription: 'Temperature >= 42°C',
        severity: planId == PlanId.l ? Severity.high : Severity.medium,
        createdAt: now.subtract(const Duration(hours: 23)),
      ),
      RiskAlert(
        id: 'aqi',
        title: 'AQI escalation',
        triggerDescription: 'AQI >= 300 for extended duration',
        severity: Severity.medium,
        createdAt: now.subtract(const Duration(days: 1, hours: 4)),
      ),
      RiskAlert(
        id: 'outage',
        title: 'Platform outage',
        triggerDescription: 'Platform downtime >= 30 minutes during peak hours',
        severity: planId == PlanId.s ? Severity.low : Severity.medium,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  void _simulatePayout(RiskAlert alert) {
    if (_simulatedAlertIds.contains(alert.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This alert has already been simulated this session.')),
      );
      return;
    }

    final amount = computePotentialPayout(planId: _selectedPlanId, alert: alert);
    final payout = Payout(
      id: 'p_${alert.id}_${_selectedPlanId.name}',
      reason: alert.title,
      date: DateTime.now(),
      amount: amount,
    );

    setState(() {
      _simulatedAlertIds.add(alert.id);
      _walletBalance += amount;
      _payouts.insert(0, payout);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payout simulated: ${inrAmt(amount)} credited to wallet.')),
    );
  }

  void _onPlanChanged(PlanId newPlan) {
    widget.onPlanChanged(newPlan);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      RiderDashboardPage(
        user: widget.user,
        planId: _selectedPlanId,
        walletBalance: _walletBalance,
        alerts: _alerts,
        payouts: _payouts,
        onGoToAlerts: () => setState(() => _tabIndex = 3),
      ),
      RiderWalletPage(
        planId: _selectedPlanId,
        walletBalance: _walletBalance,
        payouts: _payouts,
        onGoToPlans: () => setState(() => _tabIndex = 2),
      ),
      RiderPricingPage(
        planId: _selectedPlanId,
        onPlanSelected: _onPlanChanged,
      ),
      RiderAlertsPage(
        planId: _selectedPlanId,
        alerts: _alerts,
        simulatedAlertIds: _simulatedAlertIds,
        onSimulatePayout: _simulatePayout,
      ),
    ];

    final tabs = <String>['Dashboard', 'Wallet', 'Plans', 'Alerts'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Console'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        items: [
          _bottomItem(Icons.dashboard_outlined, tabs[0]),
          _bottomItem(Icons.wallet_outlined, tabs[1]),
          _bottomItem(Icons.card_membership_outlined, tabs[2]),
          _bottomItem(Icons.notifications_outlined, tabs[3]),
        ],
      ),
    );
  }

  BottomNavigationBarItem _bottomItem(IconData icon, String label) {
    return BottomNavigationBarItem(icon: Icon(icon), label: label);
  }
}

class RiderDashboardPage extends StatelessWidget {
  final AuthUser user;
  final PlanId planId;
  final double walletBalance;
  final List<RiskAlert> alerts;
  final List<Payout> payouts;
  final VoidCallback onGoToAlerts;

  const RiderDashboardPage({
    super.key,
    required this.user,
    required this.planId,
    required this.walletBalance,
    required this.alerts,
    required this.payouts,
    required this.onGoToAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final risk = predictedRiskScoreForPlan(planId);
    final weeklyPremium = computeWeeklyPremium(planId: planId, riskScore01: risk);

    final nextPayoutDate = DateTime.now().add(const Duration(days: 3));
    final activeHigh = alerts.where((a) => a.severity == Severity.high).toList();
    final aiSummary = activeHigh.isEmpty
        ? 'Signals within tolerance. Minimal risk expected this week.'
        : 'Elevated risk detected. Parametric triggers may activate payouts.';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hi ${user.email.split('@').first},',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: planId.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: planId.accent.withOpacity(0.35)),
                  ),
                  child: Text(
                    'Plan ${planId.name}',
                    style: TextStyle(color: planId.accent, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Weekly coverage cap',
                    value: inrInt(planId.weeklyCoverage),
                    icon: Icons.shield_outlined,
                    accent: planId.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    title: 'Your AI risk score',
                    value: '${risk.toStringAsFixed(2)} / 1.00',
                    icon: Icons.auto_graph_outlined,
                    accent: planId.accent,
                    sub: 'Drives dynamic pricing',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Predicted weekly premium',
                    value: inrAmt(weeklyPremium),
                    icon: Icons.receipt_long_outlined,
                    accent: planId.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    title: 'Next payout date',
                    value: formatDate(nextPayoutDate),
                    icon: Icons.schedule_outlined,
                    accent: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Prediction Summary', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      aiSummary,
                      style: TextStyle(color: Colors.black.withOpacity(0.7), height: 1.3),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _Pill(icon: Icons.near_me_outlined, text: 'Hyper-local pricing'),
                        _Pill(icon: Icons.auto_fix_high_outlined, text: 'Zero-touch payouts'),
                        _Pill(icon: Icons.location_on_outlined, text: 'Fraud scoring (prototype)'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onGoToAlerts,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('View triggers & simulate'),
                      ),
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wallet snapshot', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'Protection wallet balance: ${inrAmt(walletBalance)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    const Text('Recent payouts (mock)', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (payouts.isEmpty)
                      const Text('No payouts simulated yet. Open Alerts and run a simulation.')
                    else
                      Column(
                        children: payouts.take(4).map((p) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(width: 10, height: 10, decoration: BoxDecoration(color: planId.accent, shape: BoxShape.circle)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(p.reason, style: const TextStyle(fontWeight: FontWeight.w600))),
                                Text(inrAmt(p.amount), style: TextStyle(color: planId.accent, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final String? sub;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                border: Border.all(color: accent.withOpacity(0.35)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent)),
                  if (sub != null) ...[
                    const SizedBox(height: 4),
                    Text(sub!, style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12)),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.06),
        border: Border.all(color: cs.primary.withOpacity(0.18)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class RiderWalletPage extends StatelessWidget {
  final PlanId planId;
  final double walletBalance;
  final List<Payout> payouts;
  final VoidCallback onGoToPlans;

  const RiderWalletPage({
    super.key,
    required this.planId,
    required this.walletBalance,
    required this.payouts,
    required this.onGoToPlans,
  });

  @override
  Widget build(BuildContext context) {
    final cap = planId.weeklyCoverage.toDouble();
    final progress01 = _clamp01(walletBalance / (cap * 1.8)); // mock readiness

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Protection Wallet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balance: ${inrAmt(walletBalance)}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: planId.accent),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Weekly coverage anchor: ${inrInt(planId.weeklyCoverage)}',
                      style: TextStyle(color: Colors.black.withOpacity(0.65)),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LinearProgressIndicator(
                        value: progress01,
                        minHeight: 12,
                        backgroundColor: planId.accent.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(planId.accent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(progress01 * 100).toStringAsFixed(0)}% wallet readiness (mock).',
                      style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onGoToPlans,
                            icon: const Icon(Icons.card_membership_outlined),
                            label: const Text('Change plan'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Add funds is a placeholder in this prototype.')),
                              );
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Add funds (mock)'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Payout history (mock)', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (payouts.isEmpty)
                      const Text('No payouts yet. Open Alerts and simulate a trigger.')
                    else
                      ...payouts.take(6).map((p) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: planId.accent, shape: BoxShape.circle)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(p.reason, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text(inrAmt(p.amount), style: TextStyle(color: planId.accent, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RiderPricingPage extends StatelessWidget {
  final PlanId planId;
  final ValueChanged<PlanId> onPlanSelected;

  const RiderPricingPage({
    super.key,
    required this.planId,
    required this.onPlanSelected,
  });

  @override
  Widget build(BuildContext context) {
    final risk = predictedRiskScoreForPlan(planId);
    final premium = computeWeeklyPremium(planId: planId, riskScore01: risk);
    final cards = PlanId.values;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Pricing & Plans', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Weekly model aligned with rider payout cycles. Premium uses the formula from the README.',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.auto_graph_outlined, color: planId.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Estimated risk score: ${risk.toStringAsFixed(2)}. Estimated weekly premium: ${inrAmt(premium)}.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth > 760;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 3 : 1,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: isWide ? 1.05 : 2.1,
                  children: cards.map((p) {
                    final isSelected = p == planId;
                    final riskP = predictedRiskScoreForPlan(p);
                    final premiumP = computeWeeklyPremium(planId: p, riskScore01: riskP);

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isSelected ? p.accent.withOpacity(0.85) : Colors.black12,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: p.accent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: p.accent.withOpacity(0.35)),
                                  ),
                                  child: Icon(Icons.card_membership_outlined, color: p.accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Plan ${p.name}',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: p.accent),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Weekly coverage (cap): ${inrInt(p.weeklyCoverage)}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('Base premium (mock): ${inrAmt(p.basePremium)}', style: TextStyle(color: Colors.black.withOpacity(0.6))),
                            const SizedBox(height: 10),
                            Text('Estimated weekly premium: ${inrAmt(premiumP)}',
                                style: TextStyle(fontWeight: FontWeight.w800, color: p.accent)),
                            const SizedBox(height: 8),
                            Text('Risk score (mock AI): ${riskP.toStringAsFixed(2)}',
                                style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12)),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => onPlanSelected(p),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected ? p.accent : Colors.white,
                                  foregroundColor: isSelected ? Colors.white : p.accent,
                                  side: BorderSide(color: p.accent.withOpacity(isSelected ? 0 : 1), width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(isSelected ? 'Selected' : 'Choose Plan ${p.name}'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Triggered automatically by external signals (prototype).',
                              style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class RiderAlertsPage extends StatelessWidget {
  final PlanId planId;
  final List<RiskAlert> alerts;
  final Set<String> simulatedAlertIds;
  final void Function(RiskAlert alert) onSimulatePayout;

  const RiderAlertsPage({
    super.key,
    required this.planId,
    required this.alerts,
    required this.simulatedAlertIds,
    required this.onSimulatePayout,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Risk Alerts & Parametric Triggers',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Signals are mocked from the README: Weather, AQI, Curfew/strike feed (simulated), and Platform downtime (simulated).',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 12),
            ...alerts.map((a) {
              final isSimulated = simulatedAlertIds.contains(a.id);
              final potential = computePotentialPayout(planId: planId, alert: a);

              final severityColor = switch (a.severity) {
                Severity.low => Colors.green,
                Severity.medium => Colors.orange,
                Severity.high => Colors.red,
              };

              return Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: severityColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: severityColor.withOpacity(0.35)),
                            ),
                            child: Icon(
                              a.severity == Severity.high
                                  ? Icons.warning_amber_rounded
                                  : a.severity == Severity.medium
                                      ? Icons.notifications_active_outlined
                                      : Icons.check_circle_outline,
                              color: severityColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              a.title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ),
                          Chip(
                            backgroundColor: severityColor.withOpacity(0.12),
                            side: BorderSide(color: severityColor.withOpacity(0.35)),
                            label: Text(
                              a.severity.name.toUpperCase(),
                              style: TextStyle(fontWeight: FontWeight.w800, color: severityColor, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(a.triggerDescription, style: TextStyle(color: Colors.black.withOpacity(0.66))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Created: ${formatDate(a.createdAt)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          Text('Potential payout: ${inrAmt(potential)}', style: TextStyle(fontWeight: FontWeight.w900, color: planId.accent)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSimulated ? null : () => onSimulatePayout(a),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSimulated ? Colors.black12 : planId.accent,
                            foregroundColor: isSimulated ? Colors.black54 : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(isSimulated ? 'Simulated (this session)' : 'Simulate payout for this trigger'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Logic (mock): Loss = max(0, E - A); payout is capped by plan weekly coverage.',
                        style: TextStyle(color: Colors.black.withOpacity(0.5), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class AdminHome extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onSignOut;
  final PlanId planIdHint;

  const AdminHome({
    super.key,
    required this.user,
    required this.onSignOut,
    required this.planIdHint,
  });

  @override
  Widget build(BuildContext context) {
    final fraud = _buildFraudFlags();
    final alerts = _buildAdminTriggerFeed();
    final payouts = _buildAdminPayoutAudit(planIdHint);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome, ${user.email}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Prototype controls', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: const [
                          _AdminChip(icon: Icons.auto_awesome_outlined, text: 'Risk model (mock)'),
                          _AdminChip(icon: Icons.security_outlined, text: 'Fraud detection (prototype)'),
                          _AdminChip(icon: Icons.timeline_outlined, text: 'Trigger analytics'),
                          _AdminChip(icon: Icons.assignment_turned_in_outlined, text: 'Payout audit'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SectionTitle(title: 'Fraud Detection (prototype)'),
              _FraudFlagsCard(flags: fraud),
              const SizedBox(height: 12),
              _SectionTitle(title: 'Simulated trigger feed'),
              _TriggerFeedCard(alerts: alerts),
              const SizedBox(height: 12),
              _SectionTitle(title: 'Payout audit log (mock)'),
              _PayoutAuditCard(payouts: payouts),
            ],
          ),
        ),
      ),
    );
  }

  List<FraudFlag> _buildFraudFlags() {
    final now = DateTime.now();
    return [
      FraudFlag(
        id: 'f1',
        riderEmail: 'rider.alpha@demo.com',
        score: 0.86,
        reasons: const [
          'GPS check anomaly',
          'Rule-based behavior score spike',
          'Unusual active hours vs local weather pattern',
        ],
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      FraudFlag(
        id: 'f2',
        riderEmail: 'rider.beta@demo.com',
        score: 0.47,
        reasons: const ['Mild route deviation', 'Short-lived location drift'],
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
      ),
      FraudFlag(
        id: 'f3',
        riderEmail: 'rider.gamma@demo.com',
        score: 0.22,
        reasons: const ['No strong anomaly signals', 'Stable location adherence'],
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  List<RiskAlert> _buildAdminTriggerFeed() {
    final now = DateTime.now();
    return [
      RiskAlert(
        id: 'rain_admin_1',
        title: 'Rainfall >= 50mm',
        triggerDescription: 'Parametric trigger: rainfall window breach detected',
        severity: Severity.high,
        createdAt: now.subtract(const Duration(hours: 9)),
      ),
      RiskAlert(
        id: 'temp_admin_1',
        title: 'Temp >= 42C',
        triggerDescription: 'Heat stress window detected; delivery demand impacted',
        severity: Severity.medium,
        createdAt: now.subtract(const Duration(hours: 18)),
      ),
      RiskAlert(
        id: 'outage_admin_1',
        title: 'Platform downtime',
        triggerDescription: 'Downtime >= 30 min during peak; outage signal simulated',
        severity: Severity.medium,
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
      RiskAlert(
        id: 'aqi_admin_1',
        title: 'AQI >= 300',
        triggerDescription: 'Extended AQI escalation; curtailment expected',
        severity: Severity.medium,
        createdAt: now.subtract(const Duration(days: 2, hours: 2)),
      ),
    ];
  }

  List<Payout> _buildAdminPayoutAudit(PlanId planId) {
    final now = DateTime.now();
    return [
      Payout(
        id: 'pa1',
        reason: 'Rainfall spike (weekly auto-trigger)',
        date: now.subtract(const Duration(days: 1, hours: 6)),
        amount: computePotentialPayout(
          planId: planId,
          alert: RiskAlert(
            id: 'rain',
            title: 'Rainfall spike',
            triggerDescription: '',
            severity: Severity.high,
            createdAt: now,
          ),
        ),
      ),
      Payout(
        id: 'pa2',
        reason: 'Platform outage (parametric window)',
        date: now.subtract(const Duration(days: 2, hours: 5)),
        amount: computePotentialPayout(
          planId: planId,
          alert: RiskAlert(
            id: 'outage',
            title: 'Platform outage',
            triggerDescription: '',
            severity: Severity.medium,
            createdAt: now,
          ),
        ),
      ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
    );
  }
}

class _AdminChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _AdminChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(text),
      avatar: Icon(icon, color: cs.primary, size: 18),
      backgroundColor: cs.primary.withOpacity(0.07),
    );
  }
}

class _FraudFlagsCard extends StatelessWidget {
  final List<FraudFlag> flags;
  const _FraudFlagsCard({super.key, required this.flags});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Fraud detection uses (prototype): GPS check, rule-based anomaly scoring, and simple scoring.',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 12),
            ...flags.map((f) {
              final severityColor = f.score >= 0.75
                  ? Colors.red
                  : f.score >= 0.4
                      ? Colors.orange
                      : Colors.green;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: severityColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.riderEmail, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: f.reasons.take(3).map((r) {
                              return Chip(label: Text(r, style: const TextStyle(fontSize: 12)));
                            }).toList(),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Flag created: ${formatDate(f.createdAt)}',
                            style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Score: ${(f.score * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontWeight: FontWeight.w900, color: severityColor),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class _TriggerFeedCard extends StatelessWidget {
  final List<RiskAlert> alerts;
  const _TriggerFeedCard({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Admin view of parametric triggers (simulated feed):',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 12),
            ...alerts.map((a) {
              final severityColor = switch (a.severity) {
                Severity.low => Colors.green,
                Severity.medium => Colors.orange,
                Severity.high => Colors.red,
              };

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: severityColor.withOpacity(0.12),
                        border: Border.all(color: severityColor.withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        a.severity == Severity.high
                            ? Icons.warning_amber_rounded
                            : a.severity == Severity.medium
                                ? Icons.notifications_active_outlined
                                : Icons.check_circle_outline,
                        color: severityColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(a.triggerDescription, style: TextStyle(color: Colors.black.withOpacity(0.6))),
                          const SizedBox(height: 4),
                          Text(
                            'Created: ${formatDate(a.createdAt)}',
                            style: TextStyle(color: Colors.black.withOpacity(0.5), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      backgroundColor: severityColor.withOpacity(0.12),
                      side: BorderSide(color: severityColor.withOpacity(0.35)),
                      label: Text(
                        a.severity.name.toUpperCase(),
                        style: TextStyle(color: severityColor, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class _PayoutAuditCard extends StatelessWidget {
  final List<Payout> payouts;
  const _PayoutAuditCard({super.key, required this.payouts});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Auto-credited payouts (mock audit):',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 12),
            if (payouts.isEmpty)
              const Text('No payout records.')
            else
              ...payouts.map((p) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.reason, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('Audit ID: ${p.id}', style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('Credited: ${formatDate(p.date)}', style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(inrAmt(p.amount), style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}

