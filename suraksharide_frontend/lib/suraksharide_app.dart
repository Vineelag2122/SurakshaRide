import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

enum UserRole { rider, admin }
enum PlanId { s, m, l }
enum Severity { low, medium, high }
enum AuthMode { login, register }

class AuthAccount {
  final String password;
  final UserRole role;

  const AuthAccount({required this.password, required this.role});
}

class AuthActionResult {
  final bool success;
  final String message;

  const AuthActionResult({required this.success, required this.message});
}

class AppDatabase {
  static final AppDatabase instance = AppDatabase._internal();
  static const String dbName = 'suraksharide.db';

  static const String tableUsers = 'users';
  static const String tablePolicies = 'policies';
  static const String tableSelectedPolicies = 'selected_policies';
  static const String tablePayments = 'payments';
  static const String tablePayouts = 'payouts';
  static const String tableAlerts = 'alerts';

  AppDatabase._internal();

  final bool _useMemoryStore = kIsWeb;

  sqflite.Database? _database;
  final Map<String, Map<String, Object?>> _usersMemory = {};
  final Map<String, Map<String, Object?>> _policiesMemory = {};
  final List<Map<String, Object?>> _selectedPoliciesMemory = [];
  final List<Map<String, Object?>> _paymentsMemory = [];
  int _selectedPolicyAutoId = 0;
  int _paymentAutoId = 0;

  Future<sqflite.Database> get database async {
    if (_database != null) return _database!;
    _database = await _openDatabase();
    return _database!;
  }

  Future<sqflite.Database> _openDatabase() async {
    Future<void> onOpenWithForeignKeys(sqflite.Database db) async {
      if (!kIsWeb) {
        await db.execute('PRAGMA foreign_keys = ON');
      }
    }

    Future<sqflite.Database> openWithFfiFactory() async {
      sqflite_ffi.sqfliteFfiInit();
      sqflite.databaseFactory = sqflite_ffi.databaseFactoryFfi;
      final dbPath = await sqflite_ffi.databaseFactoryFfi.getDatabasesPath();
      final fullPath = path.join(dbPath, dbName);
      return sqflite_ffi.databaseFactoryFfi.openDatabase(
        fullPath,
        options: sqflite.OpenDatabaseOptions(
          version: 1,
          onCreate: _onCreate,
          onOpen: onOpenWithForeignKeys,
        ),
      );
    }

    final isDesktop = !kIsWeb && {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

    if (kIsWeb) {
      throw UnsupportedError('SQLite is disabled on web in this build. Use memory store.');
    }

    if (isDesktop) {
      return openWithFfiFactory();
    }

    try {
      final dbPath = await sqflite.getDatabasesPath();
      final fullPath = path.join(dbPath, dbName);
      return sqflite.openDatabase(
        fullPath,
        version: 1,
        onCreate: _onCreate,
        onOpen: onOpenWithForeignKeys,
      );
    } on StateError catch (error) {
      // Some desktop runs can still hit the global factory error path.
      if (error.toString().contains('databaseFactory not initialized')) {
        return openWithFfiFactory();
      }
      rethrow;
    }
  }

  Future<void> init() async {
    if (_useMemoryStore) {
      _seedDefaultsMemory();
      return;
    }

    final db = await database;
    await _seedDefaults(db);
  }

  void _seedDefaultsMemory() {
    final now = DateTime.now().toIso8601String();

    _usersMemory['rider@demo.com'] = {
      'email': 'rider@demo.com',
      'password': 'demo123',
      'role': UserRole.rider.name,
      'created_at': now,
    };

    _usersMemory['admin@demo.com'] = {
      'email': 'admin@demo.com',
      'password': 'demo123',
      'role': UserRole.admin.name,
      'created_at': now,
    };

    final policies = [
      {
        'id': 'policy_basic',
        'name': 'Basic Coverage',
        'description': 'Essential protection for daily commute',
        'premium_monthly': 299.0,
        'coverage_amount': 50000,
        'type': 'basic',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_premium',
        'name': 'Premium Plus',
        'description': 'Complete coverage with enhanced benefits',
        'premium_monthly': 599.0,
        'coverage_amount': 100000,
        'type': 'premium',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_comprehensive',
        'name': 'Comprehensive Shield',
        'description': 'Maximum protection with all benefits',
        'premium_monthly': 999.0,
        'coverage_amount': 250000,
        'type': 'comprehensive',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_quarterly',
        'name': 'Quarterly Combo',
        'description': 'Save more with 3-month coverage',
        'premium_monthly': 549.0,
        'coverage_amount': 150000,
        'type': 'premium',
        'is_active': 1,
        'created_at': now,
      },
    ];

    for (final policy in policies) {
      _policiesMemory[policy['id'] as String] = policy;
    }
  }

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableUsers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tablePolicies (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        premium_monthly REAL NOT NULL,
        coverage_amount INTEGER NOT NULL,
        type TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableSelectedPolicies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_email TEXT NOT NULL,
        policy_id TEXT NOT NULL,
        start_date TEXT NOT NULL,
        payment_date TEXT,
        amount_paid REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        FOREIGN KEY (user_email) REFERENCES $tableUsers(email) ON DELETE CASCADE,
        FOREIGN KEY (policy_id) REFERENCES $tablePolicies(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tablePayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_email TEXT NOT NULL,
        policy_id TEXT NOT NULL,
        amount REAL NOT NULL,
        gst REAL NOT NULL,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_email) REFERENCES $tableUsers(email) ON DELETE CASCADE,
        FOREIGN KEY (policy_id) REFERENCES $tablePolicies(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tablePayouts (
        id TEXT PRIMARY KEY,
        reason TEXT NOT NULL,
        payout_date TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableAlerts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        trigger_description TEXT NOT NULL,
        severity TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedDefaults(sqflite.Database db) async {
    final now = DateTime.now().toIso8601String();

    await db.insert(
      tableUsers,
      {
        'email': 'rider@demo.com',
        'password': 'demo123',
        'role': UserRole.rider.name,
        'created_at': now,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
    );

    await db.insert(
      tableUsers,
      {
        'email': 'admin@demo.com',
        'password': 'demo123',
        'role': UserRole.admin.name,
        'created_at': now,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
    );

    final policies = [
      {
        'id': 'policy_basic',
        'name': 'Basic Coverage',
        'description': 'Essential protection for daily commute',
        'premium_monthly': 299.0,
        'coverage_amount': 50000,
        'type': 'basic',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_premium',
        'name': 'Premium Plus',
        'description': 'Complete coverage with enhanced benefits',
        'premium_monthly': 599.0,
        'coverage_amount': 100000,
        'type': 'premium',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_comprehensive',
        'name': 'Comprehensive Shield',
        'description': 'Maximum protection with all benefits',
        'premium_monthly': 999.0,
        'coverage_amount': 250000,
        'type': 'comprehensive',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_quarterly',
        'name': 'Quarterly Combo',
        'description': 'Save more with 3-month coverage',
        'premium_monthly': 549.0,
        'coverage_amount': 150000,
        'type': 'premium',
        'is_active': 1,
        'created_at': now,
      },
    ];

    for (final policy in policies) {
      await db.insert(tablePolicies, policy, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
    }
  }

  Future<AuthActionResult> loginUser({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    if (_useMemoryStore) {
      final user = _usersMemory[email];
      if (user == null) {
        return const AuthActionResult(success: false, message: 'Account not found. Please register first.');
      }

      final storedRole = user['role'] as String;
      final storedPassword = user['password'] as String;

      if (storedRole != role.name) {
        return AuthActionResult(
          success: false,
          message: 'This email is registered as $storedRole. Select the correct role.',
        );
      }

      if (storedPassword != password) {
        return const AuthActionResult(success: false, message: 'Incorrect password.');
      }

      return const AuthActionResult(success: true, message: 'Login successful.');
    }

    final db = await database;
    final rows = await db.query(
      tableUsers,
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );

    if (rows.isEmpty) {
      return const AuthActionResult(success: false, message: 'Account not found. Please register first.');
    }

    final user = rows.first;
    final storedRole = user['role'] as String;
    final storedPassword = user['password'] as String;

    if (storedRole != role.name) {
      return AuthActionResult(
        success: false,
        message: 'This email is registered as $storedRole. Select the correct role.',
      );
    }

    if (storedPassword != password) {
      return const AuthActionResult(success: false, message: 'Incorrect password.');
    }

    return const AuthActionResult(success: true, message: 'Login successful.');
  }

  Future<AuthActionResult> registerUser({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    if (_useMemoryStore) {
      if (_usersMemory.containsKey(email)) {
        return const AuthActionResult(success: false, message: 'Email already registered. Please login.');
      }

      _usersMemory[email] = {
        'email': email,
        'password': password,
        'role': role.name,
        'created_at': DateTime.now().toIso8601String(),
      };
      return const AuthActionResult(success: true, message: 'Registration successful.');
    }

    final db = await database;

    try {
      await db.insert(
        tableUsers,
        {
          'email': email,
          'password': password,
          'role': role.name,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.abort,
      );
      return const AuthActionResult(success: true, message: 'Registration successful.');
    } on sqflite.DatabaseException catch (_) {
      return const AuthActionResult(success: false, message: 'Email already registered. Please login.');
    }
  }

  Future<void> createOrReplaceSelectedPolicy({
    required String userEmail,
    required String policyId,
    required DateTime startDate,
  }) async {
    if (_useMemoryStore) {
      for (final row in _selectedPoliciesMemory) {
        if (row['user_email'] == userEmail && (row['status'] == 'pending' || row['status'] == 'active')) {
          row['status'] = 'inactive';
        }
      }

      _selectedPolicyAutoId += 1;
      _selectedPoliciesMemory.add({
        'id': _selectedPolicyAutoId,
        'user_email': userEmail,
        'policy_id': policyId,
        'start_date': startDate.toIso8601String(),
        'payment_date': null,
        'amount_paid': 0.0,
        'status': 'pending',
      });
      return;
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        tableSelectedPolicies,
        {'status': 'inactive'},
        where: 'user_email = ? AND status IN (?, ?)',
        whereArgs: [userEmail, 'pending', 'active'],
      );

      await txn.insert(tableSelectedPolicies, {
        'user_email': userEmail,
        'policy_id': policyId,
        'start_date': startDate.toIso8601String(),
        'payment_date': null,
        'amount_paid': 0,
        'status': 'pending',
      });
    });
  }

  Future<Map<String, Object?>?> getLatestSelectedPolicy(String userEmail) async {
    if (_useMemoryStore) {
      final filtered = _selectedPoliciesMemory
          .where((row) => row['user_email'] == userEmail && (row['status'] == 'pending' || row['status'] == 'active'))
          .toList();
      if (filtered.isEmpty) return null;
      filtered.sort((a, b) => ((b['id'] as int?) ?? 0).compareTo((a['id'] as int?) ?? 0));
      return filtered.first;
    }

    final db = await database;
    final rows = await db.query(
      tableSelectedPolicies,
      where: 'user_email = ? AND status IN (?, ?)',
      whereArgs: [userEmail, 'pending', 'active'],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> activateSelectedPolicyAndRecordPayment({
    required String userEmail,
    required String policyId,
    required double premiumAmount,
    required double gstAmount,
    required double totalAmount,
    required String paymentMethod,
  }) async {
    if (_useMemoryStore) {
      final nowIso = DateTime.now().toIso8601String();
      final pendingRows = _selectedPoliciesMemory
          .where((row) => row['user_email'] == userEmail && row['policy_id'] == policyId && row['status'] == 'pending')
          .toList();

      if (pendingRows.isNotEmpty) {
        pendingRows.sort((a, b) => ((b['id'] as int?) ?? 0).compareTo((a['id'] as int?) ?? 0));
        final row = pendingRows.first;
        row['payment_date'] = nowIso;
        row['amount_paid'] = totalAmount;
        row['status'] = 'active';
      }

      _paymentAutoId += 1;
      _paymentsMemory.add({
        'id': _paymentAutoId,
        'user_email': userEmail,
        'policy_id': policyId,
        'amount': premiumAmount,
        'gst': gstAmount,
        'total': totalAmount,
        'payment_method': paymentMethod,
        'status': 'success',
        'created_at': nowIso,
      });
      return;
    }

    final db = await database;
    final nowIso = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final selectedRows = await txn.query(
        tableSelectedPolicies,
        where: 'user_email = ? AND policy_id = ? AND status = ?',
        whereArgs: [userEmail, policyId, 'pending'],
        orderBy: 'id DESC',
        limit: 1,
      );

      if (selectedRows.isNotEmpty) {
        final selectedId = selectedRows.first['id'] as int;
        await txn.update(
          tableSelectedPolicies,
          {
            'payment_date': nowIso,
            'amount_paid': totalAmount,
            'status': 'active',
          },
          where: 'id = ?',
          whereArgs: [selectedId],
        );
      }

      await txn.insert(tablePayments, {
        'user_email': userEmail,
        'policy_id': policyId,
        'amount': premiumAmount,
        'gst': gstAmount,
        'total': totalAmount,
        'payment_method': paymentMethod,
        'status': 'success',
        'created_at': nowIso,
      });
    });
  }
}

extension PlanIdView on PlanId {
  String get label => switch (this) { PlanId.s => 'S', PlanId.m => 'M', PlanId.l => 'L' };
  int get weeklyCoverage => switch (this) { PlanId.s => 2000, PlanId.m => 3500, PlanId.l => 5000 };
  double get basePremium => switch (this) { PlanId.s => 500, PlanId.m => 875, PlanId.l => 1250 };
  Color get accent => switch (this) {
    PlanId.s => const Color(0xFF0F766E),
    PlanId.m => const Color(0xFFD97706),
    PlanId.l => const Color(0xFF7C3AED),
  };
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

  const Payout({required this.id, required this.reason, required this.date, required this.amount});
}

class FraudFlag {
  final String id;
  final String riderEmail;
  final double score;
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

class InsurancePolicy {
  final String id;
  final String name;
  final String description;
  final double premiumMonthly;
  final int coverageAmount;
  final List<String> coverageDetails;
  final String type; // 'basic', 'premium', 'comprehensive'
  final bool isActive;

  const InsurancePolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.premiumMonthly,
    required this.coverageAmount,
    required this.coverageDetails,
    required this.type,
    this.isActive = false,
  });
}

class SelectedInsurance {
  final InsurancePolicy policy;
  final DateTime startDate;
  final DateTime? paymentDate;
  final double amountPaid;

  const SelectedInsurance({
    required this.policy,
    required this.startDate,
    this.paymentDate,
    this.amountPaid = 0,
  });
}

double _clamp01(double value) => value.clamp(0.0, 1.0);

String inrInt(int value) => '₹${value.toString()}';
String inrAmt(double value) => '₹${value.toStringAsFixed(0)}';

String formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

double _severityToRisk(Severity severity) {
  return switch (severity) { Severity.low => 0.15, Severity.medium => 0.45, Severity.high => 0.8 };
}

double predictedRiskScoreForPlan(PlanId planId) {
  final base = switch (planId) { PlanId.s => 0.22, PlanId.m => 0.38, PlanId.l => 0.55 };
  return _clamp01(base);
}

double computeWeeklyPremium({required PlanId planId, required double riskScore01}) {
  return planId.basePremium * (1 + 0.5 * riskScore01);
}

double computePotentialPayout({required PlanId planId, required RiskAlert alert}) {
  final cap = planId.weeklyCoverage.toDouble();
  final expected = cap * (0.55 + (_severityToRisk(alert.severity) * 0.15));
  final actual = max(0.0, expected * (1 - (0.2 + _severityToRisk(alert.severity) * 0.4)));
  return min(cap, max(0.0, expected - actual));
}

class SurakshaRideApp extends StatefulWidget {
  const SurakshaRideApp({super.key});

  @override
  State<SurakshaRideApp> createState() => _SurakshaRideAppState();
}

class _SurakshaRideAppState extends State<SurakshaRideApp> {
  AuthUser? _user;
  PlanId _selectedPlan = PlanId.s;
  late Future<void> _dbInitFuture;

  @override
  void initState() {
    super.initState();
    _dbInitFuture = AppDatabase.instance.init();
  }

  Future<AuthActionResult> _login({required String email, required String password, required UserRole role}) async {
    final result = await AppDatabase.instance.loginUser(email: email, password: password, role: role);
    if (result.success) {
      setState(() => _user = AuthUser(email: email, role: role));
    }
    return result;
  }

  Future<AuthActionResult> _register({required String email, required String password, required UserRole role}) async {
    final result = await AppDatabase.instance.registerUser(email: email, password: password, role: role);
    if (result.success) {
      setState(() => _user = AuthUser(email: email, role: role));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0F766E);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SurakshaRide',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: accent),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        appBarTheme: const AppBarTheme(backgroundColor: accent, foregroundColor: Colors.white),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF0F766E),
          unselectedItemColor: Color(0xFF64748B),
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 12,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
        ),
      ),
        home: FutureBuilder<void>(
          future: _dbInitFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            if (snapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Failed to initialize database. Please restart the app.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            if (_user == null) {
              return LoginPage(onLogin: _login, onRegister: _register);
            }

            return _user!.role == UserRole.rider
                ? RiderHome(
                    user: _user!,
                    planId: _selectedPlan,
                    onPlanChanged: (newPlan) => setState(() => _selectedPlan = newPlan),
                    onSignOut: () => setState(() => _user = null),
                  )
                : AdminHome(
                    user: _user!,
                    planIdHint: _selectedPlan,
                    onSignOut: () => setState(() => _user = null),
                  );
          },
        ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final Future<AuthActionResult> Function({required String email, required String password, required UserRole role}) onLogin;
  final Future<AuthActionResult> Function({required String email, required String password, required UserRole role}) onRegister;

  const LoginPage({super.key, required this.onLogin, required this.onRegister});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController(text: 'rider@demo.com');
  final _password = TextEditingController(text: 'demo123');
  final _confirmPassword = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _isSubmitting = false;
  UserRole _role = UserRole.rider;
  AuthMode _mode = AuthMode.login;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    final pass = _password.text;
    final confirm = _confirmPassword.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Enter a valid email address.';
        _success = null;
      });
      return;
    }

    if (pass.length < 6) {
      setState(() {
        _error = 'Password must be at least 6 characters.';
        _success = null;
      });
      return;
    }

    if (_mode == AuthMode.register && pass != confirm) {
      setState(() {
        _error = 'Password and confirm password do not match.';
        _success = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _success = null;
    });

    final result = await (_mode == AuthMode.login
        ? widget.onLogin(email: email, password: pass, role: _role)
        : widget.onRegister(email: email, password: pass, role: _role));

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (!result.success) {
      setState(() {
        _error = result.message;
        _success = null;
      });
      return;
    }

    setState(() {
      _error = null;
      _success = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < 900;
                  return Flex(
                    direction: stack ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _HeroPanel()),
                      if (!stack) const SizedBox(width: 20),
                      Expanded(child: _LoginCard()),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _LoginCard() {
    return Card(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_mode == AuthMode.login ? 'Login' : 'Register', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(_mode == AuthMode.login ? 'Login as rider or admin.' : 'Create a rider or admin account.'),
              const SizedBox(height: 16),
              SegmentedButton<AuthMode>(
                segments: const [
                  ButtonSegment(value: AuthMode.login, label: Text('Login'), icon: Icon(Icons.login_outlined)),
                  ButtonSegment(value: AuthMode.register, label: Text('Register'), icon: Icon(Icons.app_registration_outlined)),
                ],
                selected: {_mode},
                onSelectionChanged: (value) {
                  setState(() {
                    _mode = value.first;
                    _error = null;
                    _success = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(value: UserRole.rider, label: Text('Rider'), icon: Icon(Icons.directions_bike_outlined)),
                  ButtonSegment(value: UserRole.admin, label: Text('Admin'), icon: Icon(Icons.admin_panel_settings_outlined)),
                ],
                selected: {_role},
                onSelectionChanged: (value) {
                  setState(() {
                    _role = value.first;
                    _error = null;
                    _success = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              if (_mode == AuthMode.register) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPassword,
                  obscureText: !_showConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_showConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
                    ),
                  ),
                ),
              ],
              if (_success != null) ...[
                const SizedBox(height: 10),
                Text(_success!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                        )
                      : Text(_mode == AuthMode.login ? 'Login' : 'Register'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _email.text = _role == UserRole.rider ? 'rider@demo.com' : 'admin@demo.com';
                    _password.text = 'demo123';
                    _confirmPassword.text = 'demo123';
                    _error = null;
                    _success = null;
                  });
                },
                child: Text(_mode == AuthMode.login ? 'Fill demo credentials' : 'Use demo-style values'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0B1020),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('SurakshaRide', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                const Text('Weekly AI-powered parametric income protection for delivery partners.', style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text('Automatically compensates income loss caused by rain, heat, AQI spikes, curfew/strike notifications, and simulated platform downtime.', style: TextStyle(color: Colors.white.withOpacity(0.78), height: 1.5)),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _HeroChip(icon: Icons.auto_graph_outlined, text: 'AI pricing'),
                    _HeroChip(icon: Icons.bolt_outlined, text: 'Zero-touch payouts'),
                    _HeroChip(icon: Icons.shield_outlined, text: 'Fraud scoring'),
                    _HeroChip(icon: Icons.wallet_outlined, text: 'Protection wallet'),
                  ],
                ),
              ],
            ),
          ),
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
    return Chip(
      avatar: Icon(icon, size: 18, color: Colors.white),
      label: Text(text),
      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      backgroundColor: Colors.white.withOpacity(0.12),
      side: BorderSide(color: Colors.white.withOpacity(0.15)),
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
  late PlanId _selectedPlan;
  double _walletBalance = 1200;
  late List<RiskAlert> _alerts;
  final List<Payout> _payouts = [];
  final Set<String> _simulatedAlertIds = {};
  late List<InsurancePolicy> _insurancePolicies;
  late SelectedInsurance? _selectedInsurance;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.planId;
    _alerts = _buildAlerts();
    _insurancePolicies = _buildInsurancePolicies();
    _selectedInsurance = null;
    _loadPersistedInsuranceSelection();
  }

  @override
  void didUpdateWidget(covariant RiderHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.planId != widget.planId) {
      _selectedPlan = widget.planId;
      _alerts = _buildAlerts();
    }
  }

  List<RiskAlert> _buildAlerts() {
    final now = DateTime.now();
    return [
      RiskAlert(id: 'rain', title: 'Rainfall spike', triggerDescription: 'Rainfall >= 50 mm in 24 hours', severity: Severity.high, createdAt: now.subtract(const Duration(hours: 6))),
      RiskAlert(id: 'heat', title: 'Extreme heat', triggerDescription: 'Temperature >= 42°C', severity: Severity.medium, createdAt: now.subtract(const Duration(hours: 12))),
      RiskAlert(id: 'aqi', title: 'AQI escalation', triggerDescription: 'AQI >= 300 for extended duration', severity: Severity.medium, createdAt: now.subtract(const Duration(days: 1))),
      RiskAlert(id: 'outage', title: 'Platform outage', triggerDescription: 'Platform downtime >= 30 minutes during peak hours', severity: Severity.high, createdAt: now.subtract(const Duration(days: 2))),
    ];
  }

  List<InsurancePolicy> _buildInsurancePolicies() {
    return [
      InsurancePolicy(
        id: 'policy_basic',
        name: 'Basic Coverage',
        description: 'Essential protection for daily commute',
        premiumMonthly: 299,
        coverageAmount: 50000,
        coverageDetails: ['Accident coverage up to ₹50,000', 'Basic medical benefits', '24/7 customer support', 'Valid for 1 month'],
        type: 'basic',
      ),
      InsurancePolicy(
        id: 'policy_premium',
        name: 'Premium Plus',
        description: 'Complete coverage with enhanced benefits',
        premiumMonthly: 599,
        coverageAmount: 100000,
        coverageDetails: ['Accident coverage up to ₹100,000', 'Comprehensive medical benefits', 'Disability coverage', 'Free ambulance service', '24/7 priority support', 'Valid for 1 month'],
        type: 'premium',
      ),
      InsurancePolicy(
        id: 'policy_comprehensive',
        name: 'Comprehensive Shield',
        description: 'Maximum protection with all benefits',
        premiumMonthly: 999,
        coverageAmount: 250000,
        coverageDetails: ['Accident coverage up to ₹250,000', 'Full medical & hospitalization', 'Disability & loss of income', 'Free ambulance service', 'Personal accident coverage', 'Legal liability coverage', '24/7 premium support', 'Valid for 1 month'],
        type: 'comprehensive',
      ),
      InsurancePolicy(
        id: 'policy_quarterly',
        name: 'Quarterly Combo',
        description: 'Save more with 3-month coverage',
        premiumMonthly: 549,
        coverageAmount: 150000,
        coverageDetails: ['Accident coverage up to ₹150,000', 'Complete medical benefits', '25% savings vs monthly', '3-month validity', 'Free claim processing'],
        type: 'premium',
      ),
    ];
  }

  Future<void> _loadPersistedInsuranceSelection() async {
    final selectedMap = await AppDatabase.instance.getLatestSelectedPolicy(widget.user.email);
    if (!mounted || selectedMap == null) return;

    final policyId = selectedMap['policy_id'] as String;
    final policy = _insurancePolicies.where((p) => p.id == policyId).cast<InsurancePolicy?>().firstWhere((p) => p != null, orElse: () => null);
    if (policy == null) return;

    final startDateStr = selectedMap['start_date'] as String;
    final paymentDateStr = selectedMap['payment_date'] as String?;
    final amountPaidRaw = selectedMap['amount_paid'];

    setState(() {
      _selectedInsurance = SelectedInsurance(
        policy: policy,
        startDate: DateTime.tryParse(startDateStr) ?? DateTime.now(),
        paymentDate: paymentDateStr == null ? null : DateTime.tryParse(paymentDateStr),
        amountPaid: amountPaidRaw is num ? amountPaidRaw.toDouble() : 0,
      );
    });
  }

  Future<void> _handlePolicySelection(InsurancePolicy policy) async {
    final selected = SelectedInsurance(policy: policy, startDate: DateTime.now());
    setState(() {
      _selectedInsurance = selected;
      _tabIndex = 6;
    });

    await AppDatabase.instance.createOrReplaceSelectedPolicy(
      userEmail: widget.user.email,
      policyId: policy.id,
      startDate: selected.startDate,
    );
  }

  Future<void> _handlePaymentSuccess({
    required double totalAmount,
    required double gstAmount,
    required String paymentMethod,
  }) async {
    if (_selectedInsurance == null) return;

    final selected = _selectedInsurance!;
    await AppDatabase.instance.activateSelectedPolicyAndRecordPayment(
      userEmail: widget.user.email,
      policyId: selected.policy.id,
      premiumAmount: selected.policy.premiumMonthly,
      gstAmount: gstAmount,
      totalAmount: totalAmount,
      paymentMethod: paymentMethod,
    );

    if (!mounted) return;

    setState(() {
      _walletBalance -= totalAmount;
      _selectedInsurance = SelectedInsurance(
        policy: selected.policy,
        startDate: selected.startDate,
        paymentDate: DateTime.now(),
        amountPaid: totalAmount,
      );
      _tabIndex = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Insurance activated successfully! Amount: ${inrAmt(totalAmount)}')),
    );
  }

  void _simulatePayout(RiskAlert alert) {
    if (_simulatedAlertIds.contains(alert.id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This trigger was already simulated.')));
      return;
    }

    final amount = computePotentialPayout(planId: _selectedPlan, alert: alert);
    setState(() {
      _simulatedAlertIds.add(alert.id);
      _walletBalance += amount;
      _payouts.insert(0, Payout(id: 'p_${alert.id}', reason: alert.title, date: DateTime.now(), amount: amount));
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payout credited: ${inrAmt(amount)}')));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      RiderDashboardPage(
        user: widget.user,
        planId: _selectedPlan,
        walletBalance: _walletBalance,
        alerts: _alerts,
        payouts: _payouts,
        onGoToAlerts: () => setState(() => _tabIndex = 3),
        onGoToInsurance: () => setState(() => _tabIndex = 5),
        onGoToPayment: () => setState(() => _tabIndex = 6),
      ),
      RiderWalletPage(planId: _selectedPlan, walletBalance: _walletBalance, payouts: _payouts, onGoToPlans: () => setState(() => _tabIndex = 2)),
      RiderPricingPage(planId: _selectedPlan, onPlanSelected: (plan) {
        setState(() => _selectedPlan = plan);
        widget.onPlanChanged(plan);
      }),
      RiderAlertsPage(planId: _selectedPlan, alerts: _alerts, simulatedAlertIds: _simulatedAlertIds, onSimulatePayout: _simulatePayout),
      RiderInsightsPage(planId: _selectedPlan),
      InsurancePolicyPage(
        policies: _insurancePolicies,
        selectedInsurance: _selectedInsurance,
        onPolicySelected: (policy) {
          _handlePolicySelection(policy);
        },
      ),
      InsurancePaymentPage(
        selectedInsurance: _selectedInsurance,
        walletBalance: _walletBalance,
        planId: _selectedPlan,
        onPaymentSuccess: _handlePaymentSuccess,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Rider Console'), actions: [IconButton(onPressed: widget.onSignOut, icon: const Icon(Icons.logout_outlined))]),
      body: pages[_tabIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0F766E),
        unselectedItemColor: const Color(0xFF64748B),
        backgroundColor: Colors.white,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) => setState(() => _tabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.wallet_outlined), label: 'Wallet'),
          BottomNavigationBarItem(icon: Icon(Icons.card_membership_outlined), label: 'Plans'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_outlined), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), label: 'Insights'),
          BottomNavigationBarItem(icon: Icon(Icons.security_outlined), label: 'Insurance'),
          BottomNavigationBarItem(icon: Icon(Icons.payment_outlined), label: 'Payment'),
        ],
      ),
    );
  }
}

class RiderDashboardPage extends StatelessWidget {
  final AuthUser user;
  final PlanId planId;
  final double walletBalance;
  final List<RiskAlert> alerts;
  final List<Payout> payouts;
  final VoidCallback onGoToAlerts;
  final VoidCallback onGoToInsurance;
  final VoidCallback onGoToPayment;

  const RiderDashboardPage({
    super.key,
    required this.user,
    required this.planId,
    required this.walletBalance,
    required this.alerts,
    required this.payouts,
    required this.onGoToAlerts,
    required this.onGoToInsurance,
    required this.onGoToPayment,
  });

  @override
  Widget build(BuildContext context) {
    final risk = predictedRiskScoreForPlan(planId);
    final premium = computeWeeklyPremium(planId: planId, riskScore01: risk);
    final highAlerts = alerts.where((alert) => alert.severity == Severity.high).length;
    final mediumAlerts = alerts.where((alert) => alert.severity == Severity.medium).length;
    final potentialExposure = alerts.fold<double>(
      0,
      (total, alert) => total + computePotentialPayout(planId: planId, alert: alert),
    );
    final walletReadiness = _clamp01(walletBalance / (planId.weeklyCoverage * 1.8));
    final nextPayoutDate = DateTime.now().add(const Duration(days: 3));
    final topAlerts = [...alerts]
      ..sort((a, b) => _severityWeight(b.severity).compareTo(_severityWeight(a.severity)));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: planId.accent.withOpacity(0.07),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hi ${user.email.split('@').first}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Chip(
                      label: Text('Plan ${planId.label}'),
                      backgroundColor: planId.accent.withOpacity(0.12),
                      side: BorderSide(color: planId.accent.withOpacity(0.35)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Weekly AI-driven income protection overview',
                  style: TextStyle(color: Colors.black.withOpacity(0.62)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    _quickMetric('Next payout', formatDate(nextPayoutDate), planId.accent),
                    _quickMetric('Potential exposure', inrAmt(potentialExposure), planId.accent),
                    _quickMetric('High-risk windows', '$highAlerts', Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(title: 'Coverage cap', value: inrInt(planId.weeklyCoverage), accent: planId.accent, icon: Icons.shield_outlined),
            _StatCard(title: 'Risk score', value: risk.toStringAsFixed(2), accent: planId.accent, icon: Icons.auto_graph_outlined),
            _StatCard(title: 'Premium', value: inrAmt(premium), accent: planId.accent, icon: Icons.receipt_long_outlined),
            _StatCard(title: 'High alerts', value: highAlerts.toString(), accent: Colors.red, icon: Icons.warning_amber_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI summary', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  highAlerts == 0 ? 'Signals are within normal bounds for this week.' : 'Elevated conditions detected. Parametric payout windows may activate automatically.',
                  style: TextStyle(color: Colors.black.withOpacity(0.68), height: 1.4),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: walletReadiness,
                  minHeight: 8,
                  backgroundColor: planId.accent.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(planId.accent),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(walletReadiness * 100).toStringAsFixed(0)}% wallet readiness • Medium alerts: $mediumAlerts',
                  style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onGoToAlerts,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Review triggers'),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onGoToInsurance,
                      icon: const Icon(Icons.security_outlined),
                      label: const Text('Select insurance policy'),
                    ),
                    FilledButton.icon(
                      onPressed: onGoToPayment,
                      icon: const Icon(Icons.payment_outlined),
                      label: const Text('Proceed to payment'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Protection wallet', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('Balance: ${inrAmt(walletBalance)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: planId.accent)),
                const SizedBox(height: 8),
                Text('Recent payouts: ${payouts.isEmpty ? 'none yet' : payouts.length.toString()}', style: TextStyle(color: Colors.black.withOpacity(0.65))),
                const SizedBox(height: 10),
                if (payouts.isEmpty)
                  Text('No auto-credit event yet this week.', style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12))
                else
                  ...payouts.take(3).map(
                        (payout) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 10, color: planId.accent),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${payout.reason} • ${formatDate(payout.date)}')),
                              Text(inrAmt(payout.amount), style: TextStyle(fontWeight: FontWeight.w900, color: planId.accent)),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active Trigger Windows', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (topAlerts.isEmpty)
                  const Text('No active trigger windows right now.')
                else
                  ...topAlerts.take(3).map(
                        (alert) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_outlined, size: 18, color: _severityColor(alert.severity)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 2),
                                    Text(alert.triggerDescription, style: TextStyle(color: Colors.black.withOpacity(0.62), fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                inrAmt(computePotentialPayout(planId: planId, alert: alert)),
                                style: TextStyle(fontWeight: FontWeight.w900, color: planId.accent),
                              ),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickMetric(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent.withOpacity(0.08),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
        ],
      ),
    );
  }

  int _severityWeight(Severity severity) {
    return switch (severity) { Severity.high => 3, Severity.medium => 2, Severity.low => 1 };
  }

  Color _severityColor(Severity severity) {
    return switch (severity) { Severity.high => Colors.red, Severity.medium => Colors.orange, Severity.low => Colors.green };
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color accent;
  final IconData icon;

  const _StatCard({required this.title, required this.value, required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: accent)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RiderWalletPage extends StatelessWidget {
  final PlanId planId;
  final double walletBalance;
  final List<Payout> payouts;
  final VoidCallback onGoToPlans;

  const RiderWalletPage({super.key, required this.planId, required this.walletBalance, required this.payouts, required this.onGoToPlans});

  @override
  Widget build(BuildContext context) {
    final readiness = _clamp01(walletBalance / (planId.weeklyCoverage * 1.8));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Protection Wallet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Balance: ${inrAmt(walletBalance)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: planId.accent)),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: readiness, minHeight: 10),
                const SizedBox(height: 10),
                Text('${(readiness * 100).toStringAsFixed(0)}% wallet readiness', style: TextStyle(color: Colors.black.withOpacity(0.65))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: onGoToPlans, child: const Text('Change plan'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add funds is a prototype placeholder.'))),
                        child: const Text('Add funds'),
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
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Payout history', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (payouts.isEmpty)
                  const Text('No payouts yet. Open Alerts and simulate a trigger.')
                else
                  ...payouts.map((payout) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 10, color: planId.accent),
                            const SizedBox(width: 10),
                            Expanded(child: Text(payout.reason, style: const TextStyle(fontWeight: FontWeight.w700))),
                            Text(inrAmt(payout.amount), style: TextStyle(fontWeight: FontWeight.w900, color: planId.accent)),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class RiderPricingPage extends StatelessWidget {
  final PlanId planId;
  final ValueChanged<PlanId> onPlanSelected;

  const RiderPricingPage({super.key, required this.planId, required this.onPlanSelected});

  @override
  Widget build(BuildContext context) {
    final currentRisk = predictedRiskScoreForPlan(planId);
    final currentPremium = computeWeeklyPremium(planId: planId, riskScore01: currentRisk);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Pricing & Plans', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Weekly premium = base premium x (1 + 0.5 x risk score)', style: TextStyle(color: Colors.black.withOpacity(0.65))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Text('Current plan ${planId.label}: risk ${currentRisk.toStringAsFixed(2)}, estimated premium ${inrAmt(currentPremium)}', style: const TextStyle(fontWeight: FontWeight.w800)))),
        const SizedBox(height: 12),
        ...PlanId.values.map((plan) {
          final risk = predictedRiskScoreForPlan(plan);
          final premium = computeWeeklyPremium(planId: plan, riskScore01: risk);
          final selected = plan == planId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 38, height: 38, decoration: BoxDecoration(color: plan.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.card_membership_outlined, color: plan.accent)),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Plan ${plan.label}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: plan.accent))),
                        if (selected) const Chip(label: Text('Selected')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Coverage cap: ${inrInt(plan.weeklyCoverage)}'),
                    Text('Base premium: ${inrAmt(plan.basePremium)}'),
                    Text('Risk score: ${risk.toStringAsFixed(2)}'),
                    Text('Estimated weekly premium: ${inrAmt(premium)}', style: TextStyle(fontWeight: FontWeight.w900, color: plan.accent)),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: selected ? null : () => onPlanSelected(plan), child: Text(selected ? 'Selected' : 'Choose plan ${plan.label}')),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class RiderAlertsPage extends StatelessWidget {
  final PlanId planId;
  final List<RiskAlert> alerts;
  final Set<String> simulatedAlertIds;
  final ValueChanged<RiskAlert> onSimulatePayout;

  const RiderAlertsPage({super.key, required this.planId, required this.alerts, required this.simulatedAlertIds, required this.onSimulatePayout});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Parametric Triggers', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Weather, AQI, curfew/strike, and simulated downtime windows drive automatic payouts.', style: TextStyle(color: Colors.black.withOpacity(0.65))),
        const SizedBox(height: 12),
        _LossSimulatorCard(planId: planId, alerts: alerts),
        const SizedBox(height: 12),
        ...alerts.map((alert) {
          final simulated = simulatedAlertIds.contains(alert.id);
          final payout = computePotentialPayout(planId: planId, alert: alert);
          final color = switch (alert.severity) { Severity.low => Colors.green, Severity.medium => Colors.orange, Severity.high => Colors.red };

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_outlined, color: color),
                        const SizedBox(width: 8),
                        Expanded(child: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w900))),
                        Chip(label: Text(alert.severity.name.toUpperCase())),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(alert.triggerDescription),
                    const SizedBox(height: 6),
                    Text('Created: ${formatDate(alert.createdAt)}'),
                    Text('Potential payout: ${inrAmt(payout)}', style: TextStyle(fontWeight: FontWeight.w900, color: planId.accent)),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: simulated ? null : () => onSimulatePayout(alert), child: Text(simulated ? 'Simulated' : 'Simulate payout')),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _LossSimulatorCard extends StatefulWidget {
  final PlanId planId;
  final List<RiskAlert> alerts;

  const _LossSimulatorCard({required this.planId, required this.alerts});

  @override
  State<_LossSimulatorCard> createState() => _LossSimulatorCardState();
}

class _LossSimulatorCardState extends State<_LossSimulatorCard> {
  late final TextEditingController _actual;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _actual = TextEditingController(text: '300');
  }

  @override
  void dispose() {
    _actual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alerts[_selectedIndex];
    final expected = widget.planId.weeklyCoverage * (0.54 + _severityToRisk(alert.severity) * 0.18);
    final actual = double.tryParse(_actual.text) ?? 0;
    final loss = max(0.0, expected - actual);
    final payout = min(widget.planId.weeklyCoverage.toDouble(), loss);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Income-loss simulator', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Loss = max(0, E - A). Prototype uses user-input actual earnings and AI-style expected earnings.', style: TextStyle(color: Colors.black.withOpacity(0.65))),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedIndex,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Select disruption window'),
              items: List.generate(widget.alerts.length, (index) => DropdownMenuItem(value: index, child: Text(widget.alerts[index].title))),
              onChanged: (value) => setState(() => _selectedIndex = value ?? 0),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _actual,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Actual earnings (₹)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Expected', inrAmt(expected), widget.planId.accent),
                _metric('Actual', inrAmt(actual), widget.planId.accent),
                _metric('Loss / payout', '${inrAmt(loss)} / ${inrAmt(payout)}', widget.planId.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color accent) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: accent.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: accent.withOpacity(0.18))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
        ],
      ),
    );
  }
}

class RiderInsightsPage extends StatelessWidget {
  final PlanId planId;

  const RiderInsightsPage({super.key, required this.planId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Product Insights', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Architecture, impact, risks, future scope, and use cases.', style: TextStyle(color: Colors.black.withOpacity(0.65))),
        const SizedBox(height: 12),
        _infoCard('System architecture', Icons.account_tree_outlined, [
          'Mobile app for riders and admins',
          'Policy, risk, payout, fraud, and integration services',
          'PostgreSQL + Redis backend state',
          'Python AI models for risk, pricing, prediction, and fraud scoring',
        ]),
        _infoCard('Impact', Icons.trending_up_outlined, [
          'Reduces income uncertainty for gig workers',
          'Fast, transparent payouts with no claims workflow',
          'Improves retention and trust for platforms',
          'Bridges the social security gap for gig workers',
        ]),
        _infoCard('Risks', Icons.warning_amber_outlined, [
          'External data dependency',
          'Trigger calibration issues',
          'Limited platform integration access',
          'Residual fraud risk',
        ]),
        _infoCard('Future scope', Icons.explore_outlined, [
          'Ride-hailing expansion',
          'Freelancer protection',
          'Direct platform API integration',
        ]),
        _infoCard('Use cases', Icons.history_edu_outlined, [
          'Heavy rain causing earnings loss',
          'Extreme heat and AQI reducing hours',
          'App outage during peak time',
        ]),
      ],
    );
  }

  Widget _infoCard(String title, IconData icon, List<String> bullets) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: planId.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: planId.accent)),
                  const SizedBox(width: 12),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              ...bullets.map((bullet) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•'),
                        const SizedBox(width: 8),
                        Expanded(child: Text(bullet)),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              Text('Current plan ${planId.label}: coverage ${inrInt(planId.weeklyCoverage)}', style: TextStyle(color: planId.accent, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminHome extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onSignOut;
  final PlanId planIdHint;

  const AdminHome({super.key, required this.user, required this.planIdHint, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final fraudFlags = _buildFraudFlags();
    final alerts = _buildTriggerFeed();
    final payouts = _buildAuditPayouts(planIdHint);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard'), actions: [IconButton(onPressed: onSignOut, icon: const Icon(Icons.logout_outlined))]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Welcome, ${user.email}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _AdminChip(icon: Icons.auto_awesome_outlined, text: 'Risk model'),
                  _AdminChip(icon: Icons.security_outlined, text: 'Fraud detection'),
                  _AdminChip(icon: Icons.timeline_outlined, text: 'Trigger analytics'),
                  _AdminChip(icon: Icons.assignment_turned_in_outlined, text: 'Payout audit'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _section('Fraud detection', _FraudFlagsCard(flags: fraudFlags)),
          _section('Trigger feed', _TriggerFeedCard(alerts: alerts)),
          _section('Payout audit', _PayoutAuditCard(payouts: payouts, accent: planIdHint.accent)),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          child,
        ],
      ),
    );
  }

  List<FraudFlag> _buildFraudFlags() {
    final now = DateTime.now();
    return [
      FraudFlag(id: 'f1', riderEmail: 'rider.alpha@demo.com', score: 0.86, reasons: const ['GPS anomaly', 'Route deviation', 'Behavior spike'], createdAt: now.subtract(const Duration(hours: 5))),
      FraudFlag(id: 'f2', riderEmail: 'rider.beta@demo.com', score: 0.44, reasons: const ['Short drift', 'Unusual stop pattern'], createdAt: now.subtract(const Duration(days: 1))),
      FraudFlag(id: 'f3', riderEmail: 'rider.gamma@demo.com', score: 0.21, reasons: const ['No anomaly signals'], createdAt: now.subtract(const Duration(days: 2))),
    ];
  }

  List<RiskAlert> _buildTriggerFeed() {
    final now = DateTime.now();
    return [
      RiskAlert(id: 'rain_admin', title: 'Rainfall >= 50mm', triggerDescription: 'Parametric trigger detected', severity: Severity.high, createdAt: now.subtract(const Duration(hours: 9))),
      RiskAlert(id: 'heat_admin', title: 'Temperature >= 42°C', triggerDescription: 'Heat wave detected', severity: Severity.medium, createdAt: now.subtract(const Duration(hours: 16))),
      RiskAlert(id: 'outage_admin', title: 'Platform downtime', triggerDescription: 'Simulated outage during peak', severity: Severity.high, createdAt: now.subtract(const Duration(days: 1))),
    ];
  }

  List<Payout> _buildAuditPayouts(PlanId planId) {
    final triggers = _buildTriggerFeed();
    final now = DateTime.now();
    return [
      Payout(id: 'pa1', reason: 'Rainfall spike', date: now.subtract(const Duration(days: 1)), amount: computePotentialPayout(planId: planId, alert: triggers[0])),
      Payout(id: 'pa2', reason: 'Outage window', date: now.subtract(const Duration(days: 2)), amount: computePotentialPayout(planId: planId, alert: triggers[2])),
    ];
  }
}

class _AdminChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdminChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(text));
  }
}

class _FraudFlagsCard extends StatelessWidget {
  final List<FraudFlag> flags;

  const _FraudFlagsCard({required this.flags});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: flags
              .map(
                (flag) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(flag.riderEmail, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('Score: ${(flag.score * 100).toStringAsFixed(0)}%'),
                      Text('Created: ${formatDate(flag.createdAt)}', style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12)),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TriggerFeedCard extends StatelessWidget {
  final List<RiskAlert> alerts;

  const _TriggerFeedCard({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: alerts
              .map(
                (alert) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(alert.triggerDescription),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _PayoutAuditCard extends StatelessWidget {
  final List<Payout> payouts;
  final Color accent;

  const _PayoutAuditCard({required this.payouts, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: payouts
              .map(
                (payout) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${payout.reason} - ${formatDate(payout.date)}')),
                      Text(inrAmt(payout.amount), style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class InsurancePolicyPage extends StatelessWidget {
  final List<InsurancePolicy> policies;
  final SelectedInsurance? selectedInsurance;
  final ValueChanged<InsurancePolicy> onPolicySelected;

  const InsurancePolicyPage({
    super.key,
    required this.policies,
    required this.selectedInsurance,
    required this.onPolicySelected,
  });

  Color _getPolicyColor(String type) {
    return switch (type) {
      'basic' => const Color(0xFF009688),
      'premium' => const Color(0xFFD97706),
      'comprehensive' => const Color(0xFF7C3AED),
      _ => const Color(0xFF0F766E),
    };
  }

  IconData _getPolicyIcon(String type) {
    return switch (type) {
      'basic' => Icons.shield_outlined,
      'premium' => Icons.shield_sharp,
      'comprehensive' => Icons.verified_user_outlined,
      _ => Icons.security_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Insurance Policies', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Select an insurance policy to protect yourself', style: TextStyle(color: Colors.black.withOpacity(0.65))),
        const SizedBox(height: 16),
        if (selectedInsurance != null)
          Card(
            color: const Color(0xFF0F766E).withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outlined, color: Colors.green),
                      const SizedBox(width: 8),
                      Text('Active Policy: ${selectedInsurance!.policy.name}', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Validity: ${formatDate(selectedInsurance!.startDate)} to ${formatDate(selectedInsurance!.startDate.add(const Duration(days: 30)))}', style: TextStyle(color: Colors.black.withOpacity(0.6))),
                  if (selectedInsurance!.paymentDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Paid: ${inrAmt(selectedInsurance!.amountPaid)} on ${formatDate(selectedInsurance!.paymentDate!)}', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),
        if (selectedInsurance != null) const SizedBox(height: 16),
        const Text('Available Plans', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        ...policies.map((policy) {
          final color = _getPolicyColor(policy.type);
          final icon = _getPolicyIcon(policy.type);
          final isSelected = selectedInsurance?.policy.id == policy.id;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: isSelected ? 4 : 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(policy.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
                              const SizedBox(height: 4),
                              Text(policy.description, style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12)),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Chip(
                            label: const Text('Selected'),
                            backgroundColor: color.withOpacity(0.15),
                            side: BorderSide(color: color),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Premium: ${inrAmt(policy.premiumMonthly)}/month', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('Coverage: ${inrInt(policy.coverageAmount)}', style: TextStyle(color: Colors.black.withOpacity(0.65), fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: policy.coverageDetails.take(3).map((detail) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outlined, size: 16, color: color),
                            const SizedBox(width: 4),
                            Text(detail, style: const TextStyle(fontSize: 12)),
                          ],
                        );
                      }).toList(),
                    ),
                    if (policy.coverageDetails.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('+${policy.coverageDetails.length - 3} more benefits', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isSelected ? null : () => onPolicySelected(policy),
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          disabledBackgroundColor: color.withOpacity(0.5),
                        ),
                        child: Text(isSelected ? 'Already Selected' : 'Select & Pay'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
}

class InsurancePaymentPage extends StatefulWidget {
  final SelectedInsurance? selectedInsurance;
  final double walletBalance;
  final PlanId planId;
  final Future<void> Function({required double totalAmount, required double gstAmount, required String paymentMethod}) onPaymentSuccess;

  const InsurancePaymentPage({
    super.key,
    required this.selectedInsurance,
    required this.walletBalance,
    required this.planId,
    required this.onPaymentSuccess,
  });

  @override
  State<InsurancePaymentPage> createState() => _InsurancePaymentPageState();
}

class _InsurancePaymentPageState extends State<InsurancePaymentPage> {
  String _selectedPaymentMethod = 'wallet';
  bool _agreedToTerms = false;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final policy = widget.selectedInsurance?.policy;

    if (policy == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No policy selected', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Select an insurance policy first', style: TextStyle(color: Colors.black.withOpacity(0.6))),
          ],
        ),
      );
    }

    final policyColor = _getPolicyColor(policy.type);
    final gstAmount = (policy.premiumMonthly * 0.18);
    final totalAmount = policy.premiumMonthly + gstAmount;
    final canPay = widget.walletBalance >= totalAmount;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Payment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Card(
          color: policyColor.withOpacity(0.08),
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
                        color: policyColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.verified_user_outlined, color: policyColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order Summary', style: TextStyle(fontWeight: FontWeight.w900, color: policyColor)),
                          Text(policy.name, style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Price Breakdown', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _priceRow('Policy Premium', inrAmt(policy.premiumMonthly), policyColor),
                _priceRow('GST (18%)', inrAmt(gstAmount), Colors.grey, isGray: true),
                const Divider(height: 12),
                _priceRow('Total Amount', inrAmt(totalAmount), policyColor, isBold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  value: 'wallet',
                  groupValue: _selectedPaymentMethod,
                  onChanged: (value) => setState(() => _selectedPaymentMethod = value ?? 'wallet'),
                  title: const Text('Protection Wallet'),
                  subtitle: Text('Available: ${inrAmt(widget.walletBalance)}'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'card',
                  groupValue: _selectedPaymentMethod,
                  onChanged: (value) => setState(() => _selectedPaymentMethod = value ?? 'card'),
                  title: const Text('Credit/Debit Card'),
                  subtitle: const Text('Visa, Mastercard, RuPay'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'upi',
                  groupValue: _selectedPaymentMethod,
                  onChanged: (value) => setState(() => _selectedPaymentMethod = value ?? 'upi'),
                  title: const Text('UPI'),
                  subtitle: const Text('Google Pay, PhonePe, Paytm'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!canPay && _selectedPaymentMethod == 'wallet')
          Card(
            color: Colors.red.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.warning_outlined, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Insufficient Balance', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
                        Text('Needed: ${inrAmt(totalAmount)} • Available: ${inrAmt(widget.walletBalance)}', style: TextStyle(color: Colors.red.withOpacity(0.8), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Policy Details', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _detailRow('Coverage Amount', inrInt(policy.coverageAmount)),
                _detailRow('Validity', '30 days from activation'),
                _detailRow('Type', policy.type.toUpperCase()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _agreedToTerms,
          onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
          title: RichText(
            text: TextSpan(
              text: 'I agree to the ',
              style: TextStyle(color: Colors.black.withOpacity(0.7)),
              children: [
                TextSpan(
                  text: 'Terms & Conditions',
                  style: TextStyle(color: policyColor, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' and ',
                  style: TextStyle(color: Colors.black.withOpacity(0.7)),
                ),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(color: policyColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (!_agreedToTerms || (_selectedPaymentMethod == 'wallet' && !canPay) || _isProcessing)
              ? null
              : () => _processPayment(totalAmount, policyColor),
          style: FilledButton.styleFrom(
            backgroundColor: policyColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _isProcessing
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                    SizedBox(width: 12),
                    Text('Processing...'),
                  ],
                )
              : Text('Complete Payment - ${inrAmt(totalAmount)}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _isProcessing ? null : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment cancelled'))),
          child: const Text('Cancel'),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _processPayment(double amount, Color color) {
    final policy = widget.selectedInsurance?.policy;
    if (policy == null) return;
    final gstAmount = policy.premiumMonthly * 0.18;

    setState(() => _isProcessing = true);

    Future.delayed(const Duration(seconds: 2), () async {
      if (mounted) {
        await widget.onPaymentSuccess(
          totalAmount: amount,
          gstAmount: gstAmount,
          paymentMethod: _selectedPaymentMethod,
        );
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      }
    });
  }

  Widget _priceRow(String label, String amount, Color color, {bool isGray = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isGray ? FontWeight.w500 : FontWeight.w700, color: isGray ? Colors.black.withOpacity(0.6) : null)),
          Text(amount, style: TextStyle(fontWeight: isBold ? FontWeight.w900 : FontWeight.w700, color: isBold ? color : null, fontSize: isBold ? 16 : 14)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.black.withOpacity(0.6))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Color _getPolicyColor(String type) {
    return switch (type) {
      'basic' => const Color(0xFF009688),
      'premium' => const Color(0xFFD97706),
      'comprehensive' => const Color(0xFF7C3AED),
      _ => const Color(0xFF0F766E),
    };
  }
}