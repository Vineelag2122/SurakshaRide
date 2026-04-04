import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:xml/xml.dart' as xml;

import 'url_opener_stub.dart' if (dart.library.html) 'url_opener_web.dart';

enum UserRole { rider, admin }
enum PlanId { s, m, l }
enum Severity { low, medium, high }
enum AuthMode { login, register }
enum TriggerCategory { appDowntime, rainfall, extremeHeat, pollution, war, lockdown }

T? _firstOrNull<T>(Iterable<T> items) {
  if (items.isEmpty) return null;
  return items.first;
}

class NewsTriggerCandidate {
  final String id;
  final String title;
  final String source;
  final String url;
  final String sourcePageUrl;
  final String suggestedLocation;
  final DateTime publishedAt;
  final TriggerCategory category;
  final Severity severity;
  final String summary;

  const NewsTriggerCandidate({
    required this.id,
    required this.title,
    required this.source,
    required this.url,
    this.sourcePageUrl = '',
    this.suggestedLocation = 'all',
    required this.publishedAt,
    required this.category,
    required this.severity,
    required this.summary,
  });
}

class NewsTriggerScraper {
  static final List<String> _rssSources = [
    'https://news.google.com/rss/search?q=platform+outage+OR+app+down+OR+server+outage&hl=en-IN&gl=IN&ceid=IN:en',
    'https://news.google.com/rss/search?q=heavy+rainfall+OR+flood+warning&hl=en-IN&gl=IN&ceid=IN:en',
    'https://news.google.com/rss/search?q=war+conflict+breaking&hl=en-IN&gl=IN&ceid=IN:en',
    'https://news.google.com/rss/search?q=lockdown+curfew+government+order&hl=en-IN&gl=IN&ceid=IN:en',
  ];

  static Future<List<NewsTriggerCandidate>> fetchCandidates() async {
    final results = <NewsTriggerCandidate>[];

    for (final sourceUrl in _rssSources) {
      try {
        final response = await http.get(Uri.parse(sourceUrl));
        if (response.statusCode != 200) continue;

        final document = xml.XmlDocument.parse(response.body);
        final channel = _firstOrNull(document.findAllElements('channel'));
        final sourceName = _firstOrNull(channel?.findElements('title') ?? const <xml.XmlElement>[])?.innerText.trim() ?? 'News feed';

        for (final item in document.findAllElements('item').take(8)) {
          final title = _firstOrNull(item.findElements('title'))?.innerText.trim() ?? '';
          final description = _firstOrNull(item.findElements('description'))?.innerText.trim() ?? '';
          final link = _firstOrNull(item.findElements('link'))?.innerText.trim() ?? '';
          final pubDateRaw = _firstOrNull(item.findElements('pubDate'))?.innerText.trim();
          final combined = '${title.toLowerCase()} ${description.toLowerCase()}';
          final category = _detectCategory(combined);
          if (category == null) continue;

          results.add(
            NewsTriggerCandidate(
              id: '${category.name}_${title.hashCode}_${link.hashCode}',
              title: title.isEmpty ? _categoryLabel(category) : title,
              source: sourceName,
              url: link,
              sourcePageUrl: sourceUrl,
              suggestedLocation: 'all',
              publishedAt: DateTime.tryParse(pubDateRaw ?? '') ?? DateTime.now(),
              category: category,
              severity: _severityForCategory(category),
              summary: description.isEmpty ? 'Potential uncontrollable event from news feed.' : description,
            ),
          );
        }
      } catch (_) {
        // Ignore source-level failures and continue with other feeds.
      }
    }

    if (results.isEmpty) {
      return _fallbackCandidates();
    }

    final byId = <String, NewsTriggerCandidate>{};
    for (final candidate in results) {
      byId[candidate.id] = candidate;
    }
    return byId.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  static TriggerCategory? _detectCategory(String text) {
    if (text.contains('app down') || text.contains('outage') || text.contains('server down') || text.contains('service disruption')) {
      return TriggerCategory.appDowntime;
    }
    if (text.contains('rainfall') || text.contains('heavy rain') || text.contains('flood') || text.contains('storm')) {
      return TriggerCategory.rainfall;
    }
    if (text.contains('heatwave') || text.contains('extreme heat') || text.contains('temperature') || text.contains('hot weather')) {
      return TriggerCategory.extremeHeat;
    }
    if (text.contains('aqi') || text.contains('pollution') || text.contains('smog') || text.contains('pm2.5')) {
      return TriggerCategory.pollution;
    }
    if (text.contains('war') || text.contains('armed conflict') || text.contains('missile') || text.contains('air strike')) {
      return TriggerCategory.war;
    }
    if (text.contains('lockdown') || text.contains('curfew') || text.contains('movement restriction')) {
      return TriggerCategory.lockdown;
    }
    return null;
  }

  static Severity _severityForCategory(TriggerCategory category) {
    return switch (category) {
      TriggerCategory.appDowntime => Severity.high,
      TriggerCategory.rainfall => Severity.medium,
      TriggerCategory.extremeHeat => Severity.medium,
      TriggerCategory.pollution => Severity.medium,
      TriggerCategory.war => Severity.high,
      TriggerCategory.lockdown => Severity.high,
    };
  }

  static String _categoryLabel(TriggerCategory category) {
    return switch (category) {
      TriggerCategory.appDowntime => 'App downtime risk',
      TriggerCategory.rainfall => 'Rainfall risk',
      TriggerCategory.extremeHeat => 'Extreme heat risk',
      TriggerCategory.pollution => 'Severe pollution risk',
      TriggerCategory.war => 'War/conflict risk',
      TriggerCategory.lockdown => 'Lockdown/curfew risk',
    };
  }

  static List<NewsTriggerCandidate> _fallbackCandidates() {
    final now = DateTime.now();
    return [
      NewsTriggerCandidate(
        id: 'fallback_outage_${now.millisecondsSinceEpoch}',
        title: 'Platform service outage reported',
        source: 'Fallback feed',
        url: '',
        sourcePageUrl: '',
        suggestedLocation: 'all',
        publishedAt: now.subtract(const Duration(hours: 2)),
        category: TriggerCategory.appDowntime,
        severity: Severity.high,
        summary: 'Multiple outage reports found. Awaiting admin validation.',
      ),
      NewsTriggerCandidate(
        id: 'fallback_rain_${now.millisecondsSinceEpoch}',
        title: 'Heavy rainfall alert issued',
        source: 'Fallback feed',
        url: '',
        sourcePageUrl: '',
        suggestedLocation: 'all',
        publishedAt: now.subtract(const Duration(hours: 3)),
        category: TriggerCategory.rainfall,
        severity: Severity.medium,
        summary: 'Heavy rain advisory published in operating zones.',
      ),
    ];
  }
}

class _CityGeo {
  final String city;
  final double lat;
  final double lon;

  const _CityGeo(this.city, this.lat, this.lon);
}

class ExternalTriggerEngine {
  static const List<_CityGeo> _cities = [
    _CityGeo('Bengaluru', 12.9716, 77.5946),
    _CityGeo('Mumbai', 19.0760, 72.8777),
    _CityGeo('Delhi', 28.6139, 77.2090),
  ];

  static Future<List<NewsTriggerCandidate>> fetchCandidates() async {
    final now = DateTime.now();
    final results = <NewsTriggerCandidate>[];

    for (final city in _cities) {
      results.addAll(await _fetchWeatherAndAqi(city));
      results.add(_mockPlatformOutage(city.city, now));
      final curfew = _mockCurfew(city.city, now);
      if (curfew != null) {
        results.add(curfew);
      }
    }

    final byId = <String, NewsTriggerCandidate>{};
    for (final candidate in results) {
      byId[candidate.id] = candidate;
    }
    return byId.values.toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  static Future<List<NewsTriggerCandidate>> _fetchWeatherAndAqi(_CityGeo city) async {
    final now = DateTime.now();
    final list = <NewsTriggerCandidate>[];

    try {
      final weatherUrl =
          'https://api.open-meteo.com/v1/forecast?latitude=${city.lat}&longitude=${city.lon}&current=temperature_2m,rain';
      final weatherResponse = await http.get(Uri.parse(weatherUrl));
      if (weatherResponse.statusCode == 200) {
        final weatherJson = jsonDecode(weatherResponse.body) as Map<String, dynamic>;
        final current = (weatherJson['current'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 0;
        final rain = (current['rain'] as num?)?.toDouble() ?? 0;

        if (rain >= 8) {
          list.add(
            NewsTriggerCandidate(
              id: 'wx_rain_${city.city}_${now.hour}_${now.day}',
              title: 'Heavy rainfall risk detected in ${city.city}',
              source: 'Open-Meteo Weather API',
              url: weatherUrl,
              sourcePageUrl: weatherUrl,
              suggestedLocation: city.city,
              publishedAt: now,
              category: TriggerCategory.rainfall,
              severity: Severity.high,
              summary: 'Rain intensity is high enough to disrupt delivery operations in ${city.city}.',
            ),
          );
        }

        if (temp >= 40) {
          list.add(
            NewsTriggerCandidate(
              id: 'wx_heat_${city.city}_${now.hour}_${now.day}',
              title: 'Extreme heat risk detected in ${city.city}',
              source: 'Open-Meteo Weather API',
              url: weatherUrl,
              sourcePageUrl: weatherUrl,
              suggestedLocation: city.city,
              publishedAt: now,
              category: TriggerCategory.extremeHeat,
              severity: Severity.medium,
              summary: 'Temperature crossed safe outdoor threshold in ${city.city}.',
            ),
          );
        }
      }
    } catch (_) {
      // Continue with other sources if weather API is unavailable.
    }

    try {
      final aqiUrl =
          'https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${city.lat}&longitude=${city.lon}&current=us_aqi,pm2_5';
      final aqiResponse = await http.get(Uri.parse(aqiUrl));
      if (aqiResponse.statusCode == 200) {
        final aqiJson = jsonDecode(aqiResponse.body) as Map<String, dynamic>;
        final current = (aqiJson['current'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final usAqi = (current['us_aqi'] as num?)?.toDouble() ?? 0;
        if (usAqi >= 180) {
          list.add(
            NewsTriggerCandidate(
              id: 'aqi_${city.city}_${now.hour}_${now.day}',
              title: 'Severe pollution risk detected in ${city.city}',
              source: 'Open-Meteo Air Quality API',
              url: aqiUrl,
              sourcePageUrl: aqiUrl,
              suggestedLocation: city.city,
              publishedAt: now,
              category: TriggerCategory.pollution,
              severity: Severity.medium,
              summary: 'AQI levels are unsafe for prolonged rider activity in ${city.city}.',
            ),
          );
        }
      }
    } catch (_) {
      // Continue with mock signals if AQI API is unavailable.
    }

    return list;
  }

  static NewsTriggerCandidate _mockPlatformOutage(String city, DateTime now) {
    return NewsTriggerCandidate(
      id: 'mock_outage_${city}_${now.hour}_${now.day}',
      title: 'Simulated platform outage watch - $city',
      source: 'Mock Platform Ops API',
      url: '',
      sourcePageUrl: 'https://www.githubstatus.com/',
      suggestedLocation: city,
      publishedAt: now.subtract(const Duration(minutes: 6)),
      category: TriggerCategory.appDowntime,
      severity: Severity.medium,
      summary: 'Order assignment degradation detected in $city. Trigger created for admin review.',
    );
  }

  static NewsTriggerCandidate? _mockCurfew(String city, DateTime now) {
    if (now.hour < 21) return null;
    return NewsTriggerCandidate(
      id: 'mock_curfew_${city}_${now.day}',
      title: 'Simulated late-hour curfew advisory - $city',
      source: 'Mock Civic Alert Feed',
      url: '',
      sourcePageUrl: 'https://www.ndma.gov.in/',
      suggestedLocation: city,
      publishedAt: now,
      category: TriggerCategory.lockdown,
      severity: Severity.high,
      summary: 'Late-hour movement restrictions may reduce delivery windows in $city.',
    );
  }
}

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
        'name': 'Income Shield - Basic',
        'description': 'Weekly income-loss protection for local disruptions',
        'premium_monthly': 299.0,
        'coverage_amount': 50000,
        'type': 'basic',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_premium',
        'name': 'Income Shield - Plus',
        'description': 'Higher weekly income protection for high-risk zones',
        'premium_monthly': 599.0,
        'coverage_amount': 100000,
        'type': 'premium',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_comprehensive',
        'name': 'Income Shield - Max',
        'description': 'Maximum weekly earnings protection for full-time riders',
        'premium_monthly': 999.0,
        'coverage_amount': 250000,
        'type': 'comprehensive',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_quarterly',
        'name': 'Income Shield - Smart Saver',
        'description': 'Lower weekly premium for stable riding zones',
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
        'name': 'Income Shield - Basic',
        'description': 'Weekly income-loss protection for local disruptions',
        'premium_monthly': 299.0,
        'coverage_amount': 50000,
        'type': 'basic',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_premium',
        'name': 'Income Shield - Plus',
        'description': 'Higher weekly income protection for high-risk zones',
        'premium_monthly': 599.0,
        'coverage_amount': 100000,
        'type': 'premium',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_comprehensive',
        'name': 'Income Shield - Max',
        'description': 'Maximum weekly earnings protection for full-time riders',
        'premium_monthly': 999.0,
        'coverage_amount': 250000,
        'type': 'comprehensive',
        'is_active': 1,
        'created_at': now,
      },
      {
        'id': 'policy_quarterly',
        'name': 'Income Shield - Smart Saver',
        'description': 'Lower weekly premium for stable riding zones',
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
    if (role == UserRole.admin) {
      return const AuthActionResult(success: false, message: 'Admin account creation is disabled. Admin can only login.');
    }

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
  final String source;
  final String sourceUrl;
  final String sourcePageUrl;
  final String affectedLocation;
  final Severity severity;
  final DateTime createdAt;

  const RiskAlert({
    required this.id,
    required this.title,
    required this.triggerDescription,
    required this.source,
    this.sourceUrl = '',
    this.sourcePageUrl = '',
    this.affectedLocation = 'all',
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

class AdminAnalyticsSnapshot {
  final int pendingTriggers;
  final int approvedTriggers;
  final int criticalFraudFlags;
  final int warningFraudFlags;
  final int highSeverityTriggers;
  final int sourceCount;
  final double estimatedWeeklyExposure;
  final Map<String, int> locationDistribution;

  const AdminAnalyticsSnapshot({
    required this.pendingTriggers,
    required this.approvedTriggers,
    required this.criticalFraudFlags,
    required this.warningFraudFlags,
    required this.highSeverityTriggers,
    required this.sourceCount,
    required this.estimatedWeeklyExposure,
    required this.locationDistribution,
  });
}

class InsurancePolicy {
  final String id;
  final String name;
  final String description;
  final double weeklyPremium;
  final double premiumMonthly;
  final int coverageAmount;
  final List<String> coverageDetails;
  final String type; // 'basic', 'premium', 'comprehensive'
  final bool isActive;

  const InsurancePolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.weeklyPremium,
    double? premiumMonthly,
    required this.coverageAmount,
    required this.coverageDetails,
    required this.type,
    this.isActive = false,
  }) : premiumMonthly = premiumMonthly ?? weeklyPremium;
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

class RiderSecurityProfile {
  final String aadhaarNumber;
  final String operatingLocation;
  final String workProofType;
  final String workProofId;
  final String upiId;
  final String emergencyPhone;
  final String payoutPin;
  final bool enable2Fa;
  final bool consentAccepted;
  final bool isVerified;

  const RiderSecurityProfile({
    this.aadhaarNumber = '',
    this.operatingLocation = '',
    this.workProofType = 'Delivery ID',
    this.workProofId = '',
    this.upiId = '',
    this.emergencyPhone = '',
    this.payoutPin = '',
    this.enable2Fa = false,
    this.consentAccepted = false,
    this.isVerified = false,
  });

  RiderSecurityProfile copyWith({
    String? aadhaarNumber,
    String? operatingLocation,
    String? workProofType,
    String? workProofId,
    String? upiId,
    String? emergencyPhone,
    String? payoutPin,
    bool? enable2Fa,
    bool? consentAccepted,
    bool? isVerified,
  }) {
    return RiderSecurityProfile(
      aadhaarNumber: aadhaarNumber ?? this.aadhaarNumber,
      operatingLocation: operatingLocation ?? this.operatingLocation,
      workProofType: workProofType ?? this.workProofType,
      workProofId: workProofId ?? this.workProofId,
      upiId: upiId ?? this.upiId,
      emergencyPhone: emergencyPhone ?? this.emergencyPhone,
      payoutPin: payoutPin ?? this.payoutPin,
      enable2Fa: enable2Fa ?? this.enable2Fa,
      consentAccepted: consentAccepted ?? this.consentAccepted,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}

double _clamp01(double value) => value.clamp(0.0, 1.0);

String inrInt(int value) => '₹${value.toString()}';
String inrAmt(double value) => '₹${value.toStringAsFixed(0)}';

String formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _normalizeLocation(String value) {
  final lowered = value.trim().toLowerCase();
  if (lowered.isEmpty) return '';
  if (lowered == 'all' || lowered == 'all locations' || lowered == 'any' || lowered == 'pan india' || lowered == 'nationwide') {
    return 'all';
  }
  return lowered;
}

bool isAlertRelevantForLocation(RiskAlert alert, String riderLocation) {
  final alertLocation = _normalizeLocation(alert.affectedLocation);
  if (alertLocation.isEmpty || alertLocation == 'all') return true;

  final rider = _normalizeLocation(riderLocation);
  if (rider.isEmpty) return false;

  return rider.contains(alertLocation) || alertLocation.contains(rider);
}

String alertTriggerSource(RiskAlert alert) {
  final area = _normalizeLocation(alert.affectedLocation) == 'all' || alert.affectedLocation.trim().isEmpty
      ? 'All locations'
      : alert.affectedLocation;
  if (alert.sourceUrl.isNotEmpty) {
    return 'Source: ${alert.source} • Affected area: $area • ${alert.sourceUrl}';
  }
  return 'Source: ${alert.source} • Affected area: $area';
}

String alertCorrectionTip(RiskAlert alert) {
  return 'If you think this is incorrect, contact support from Help and request a trigger review.';
}

String riderAlertLabel(RiskAlert alert) {
  return switch (alert.id) {
    'rain' => 'Earnings Risk Window A',
    'heat' => 'Earnings Risk Window B',
    'aqi' => 'Earnings Risk Window C',
    'outage' => 'Earnings Risk Window D',
    _ => 'Earnings Risk Window',
  };
}

bool isOpenableUrl(String url) {
  final value = url.trim();
  if (value.isEmpty) return false;

  final uri = Uri.tryParse(value);
  if (uri == null) return false;

  final hasWebScheme = uri.scheme == 'http' || uri.scheme == 'https';
  if (!hasWebScheme) return false;
  if (uri.host.isEmpty) return false;

  final host = uri.host.toLowerCase();
  if (host.contains('example.com') || host == 'localhost') return false;
  return true;
}

String _searchUrl(String query) {
  return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(query)}';
}

String bestCandidateSourcePageUrl(NewsTriggerCandidate candidate) {
  if (isOpenableUrl(candidate.sourcePageUrl)) return candidate.sourcePageUrl;
  if (isOpenableUrl(candidate.url)) return candidate.url;
  return _searchUrl('${candidate.source} ${candidate.title} ${candidate.suggestedLocation}');
}

String bestCandidateArticleUrl(NewsTriggerCandidate candidate) {
  if (isOpenableUrl(candidate.url)) return candidate.url;
  return _searchUrl('${candidate.title} ${candidate.source}');
}

String bestAlertSourcePageUrl(RiskAlert alert) {
  if (isOpenableUrl(alert.sourcePageUrl)) return alert.sourcePageUrl;
  if (isOpenableUrl(alert.sourceUrl)) return alert.sourceUrl;
  return _searchUrl('${alert.source} ${alert.title} ${alert.affectedLocation}');
}

String bestAlertArticleUrl(RiskAlert alert) {
  if (isOpenableUrl(alert.sourceUrl)) return alert.sourceUrl;
  return _searchUrl('${alert.title} ${alert.source}');
}

Future<void> openSourceLink(BuildContext context, String sourceUrl) async {
  var normalized = sourceUrl.trim();
  if (normalized.isEmpty) return;

  final hasScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(normalized);
  if (!hasScheme) {
    normalized = 'https://$normalized';
  }

  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invalid source URL.')),
    );
    return;
  }

  final encoded = uri.toString();
  final opened = await openExternalUrl(encoded);

  if (!opened && context.mounted) {
    await Clipboard.setData(ClipboardData(text: encoded));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open link directly. URL copied to clipboard.')),
    );
  }
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
  final List<NewsTriggerCandidate> _pendingNewsTriggers = [];
  final List<RiskAlert> _approvedAlerts = [];
  final List<FraudFlag> _fraudFlags = [];
  bool? _isFetchingNewsTriggers = false;

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

  Future<void> _fetchNewsTriggers() async {
    if ((_isFetchingNewsTriggers ?? false)) return;
    setState(() => _isFetchingNewsTriggers = true);

    final fetchedNews = await NewsTriggerScraper.fetchCandidates();
    final fetchedExternal = await ExternalTriggerEngine.fetchCandidates();
    final fetched = [...fetchedNews, ...fetchedExternal];
    final existingIds = _pendingNewsTriggers.map((e) => e.id).toSet();
    final approvedIds = _approvedAlerts.map((e) => e.id).toSet();

    final newOnes = fetched.where((candidate) {
      final adminAlertId = 'approved_${candidate.id}';
      return !existingIds.contains(candidate.id) && !approvedIds.contains(adminAlertId);
    });

    setState(() {
      _pendingNewsTriggers.insertAll(0, newOnes);
      _isFetchingNewsTriggers = false;
    });
  }

  void _approveNewsTrigger(String triggerId, String affectedLocation) {
    final index = _pendingNewsTriggers.indexWhere((e) => e.id == triggerId);
    if (index == -1) return;
    final candidate = _pendingNewsTriggers.removeAt(index);
    final normalizedLocation = _normalizeLocation(affectedLocation);

    final alert = RiskAlert(
      id: 'approved_${candidate.id}',
      title: _adminCategoryLabel(candidate.category),
      triggerDescription: candidate.summary,
      source: candidate.source,
      sourceUrl: candidate.url,
      sourcePageUrl: candidate.sourcePageUrl,
      affectedLocation: normalizedLocation.isEmpty ? 'all' : affectedLocation.trim(),
      severity: candidate.severity,
      createdAt: DateTime.now(),
    );

    setState(() {
      _approvedAlerts.insert(0, alert);
    });
  }

  void _rejectNewsTrigger(String triggerId) {
    setState(() {
      _pendingNewsTriggers.removeWhere((e) => e.id == triggerId);
    });
  }

  void _recordFraudFlag(FraudFlag flag) {
    setState(() {
      final exists = _fraudFlags.any((f) => f.id == flag.id);
      if (!exists) {
        _fraudFlags.insert(0, flag);
      }
    });
  }

  String _adminCategoryLabel(TriggerCategory category) {
    return switch (category) {
      TriggerCategory.appDowntime => 'App downtime event',
      TriggerCategory.rainfall => 'Rainfall disruption event',
      TriggerCategory.extremeHeat => 'Extreme heat disruption event',
      TriggerCategory.pollution => 'Severe pollution disruption event',
      TriggerCategory.war => 'War/conflict event',
      TriggerCategory.lockdown => 'Lockdown/curfew event',
    };
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
                    approvedAlerts: _approvedAlerts,
                    onFraudFlagGenerated: _recordFraudFlag,
                    onPlanChanged: (newPlan) => setState(() => _selectedPlan = newPlan),
                    onSignOut: () => setState(() => _user = null),
                  )
                : AdminHome(
                    user: _user!,
                    planIdHint: _selectedPlan,
                    pendingNewsTriggers: _pendingNewsTriggers,
                    approvedAlerts: _approvedAlerts,
                    fraudFlags: _fraudFlags,
                    isFetchingNewsTriggers: _isFetchingNewsTriggers ?? false,
                    onFetchNewsTriggers: _fetchNewsTriggers,
                    onApproveNewsTrigger: _approveNewsTrigger,
                    onRejectNewsTrigger: _rejectNewsTrigger,
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
    final effectiveRole = _mode == AuthMode.register ? UserRole.rider : _role;

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
      ? widget.onLogin(email: email, password: pass, role: effectiveRole)
      : widget.onRegister(email: email, password: pass, role: effectiveRole));

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
              Text(_role == UserRole.admin ? 'Admin can only login.' : (_mode == AuthMode.login ? 'Login as rider or admin.' : 'Create a rider account.')),
              const SizedBox(height: 16),
              if (_role == UserRole.admin)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.25)),
                    color: const Color(0xFF0F766E).withOpacity(0.08),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.admin_panel_settings_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Admin login only', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                )
              else
                SegmentedButton<AuthMode>(
                  segments: const [
                    ButtonSegment(value: AuthMode.login, label: Text('Login'), icon: Icon(Icons.login_outlined)),
                    ButtonSegment(value: AuthMode.register, label: Text('Register'), icon: Icon(Icons.app_registration_outlined)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) {
                    setState(() {
                      _mode = value.first;
                      if (_mode == AuthMode.register) {
                        _role = UserRole.rider;
                      }
                      _error = null;
                      _success = null;
                    });
                  },
                ),
              const SizedBox(height: 16),
              if (_mode == AuthMode.login)
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(value: UserRole.rider, label: Text('Rider'), icon: Icon(Icons.directions_bike_outlined)),
                    ButtonSegment(value: UserRole.admin, label: Text('Admin'), icon: Icon(Icons.admin_panel_settings_outlined)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (value) {
                    setState(() {
                      _role = value.first;
                      if (_role == UserRole.admin) {
                        _mode = AuthMode.login;
                      }
                      _error = null;
                      _success = null;
                    });
                  },
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.25)),
                    color: const Color(0xFF0F766E).withOpacity(0.08),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.directions_bike_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Registering as Rider', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (_mode == AuthMode.register)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Admin accounts are managed internally and can only login.',
                    style: TextStyle(color: Colors.black.withOpacity(0.62), fontSize: 12),
                  ),
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
  final List<RiskAlert>? approvedAlerts;
  final ValueChanged<FraudFlag>? onFraudFlagGenerated;
  final ValueChanged<PlanId> onPlanChanged;
  final VoidCallback onSignOut;

  const RiderHome({
    super.key,
    required this.user,
    required this.planId,
    this.approvedAlerts,
    this.onFraudFlagGenerated,
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
  final Set<String> _autoProcessedAlertIds = {};
  final Set<String> _reviewRequiredAlertIds = {};
  late List<InsurancePolicy> _insurancePolicies;
  late SelectedInsurance? _selectedInsurance;
  RiderSecurityProfile _securityProfile = const RiderSecurityProfile();

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.planId;
    _alerts = const <RiskAlert>[];
    _refreshLocationFilteredAlerts();
    _autoProcessAlertsIfEligible();
    _insurancePolicies = _buildInsurancePolicies();
    _selectedInsurance = null;
    _loadPersistedInsuranceSelection();
  }

  @override
  void didUpdateWidget(covariant RiderHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.planId != widget.planId) {
      _selectedPlan = widget.planId;
    }
    _refreshLocationFilteredAlerts();
    _autoProcessAlertsIfEligible();
  }

  void _refreshLocationFilteredAlerts() {
    final incoming = [...(widget.approvedAlerts ?? const <RiskAlert>[])];
    _alerts = incoming.where((alert) => isAlertRelevantForLocation(alert, _securityProfile.operatingLocation)).toList();
  }

  void _autoProcessAlertsIfEligible() {
    if (!_securityProfile.isVerified) return;

    bool changed = false;
    for (final alert in _alerts) {
      if (_autoProcessedAlertIds.contains(alert.id) || _simulatedAlertIds.contains(alert.id)) {
        continue;
      }

      final amount = computePotentialPayout(planId: _selectedPlan, alert: alert);
      final fraudAssessment = _assessFraudRisk(alert: alert, payoutAmount: amount);

      if (fraudAssessment.score >= 0.72) {
        _reviewRequiredAlertIds.add(alert.id);
        widget.onFraudFlagGenerated?.call(
          FraudFlag(
            id: 'fraud_${widget.user.email}_${alert.id}',
            riderEmail: widget.user.email,
            score: fraudAssessment.score,
            reasons: fraudAssessment.reasons,
            createdAt: DateTime.now(),
          ),
        );
        changed = true;
        continue;
      }

      if (fraudAssessment.score >= 0.45) {
        widget.onFraudFlagGenerated?.call(
          FraudFlag(
            id: 'fraud_warn_${widget.user.email}_${alert.id}',
            riderEmail: widget.user.email,
            score: fraudAssessment.score,
            reasons: fraudAssessment.reasons,
            createdAt: DateTime.now(),
          ),
        );
      }

      _autoProcessedAlertIds.add(alert.id);
      _simulatedAlertIds.add(alert.id);
      _walletBalance += amount;
      _payouts.insert(
        0,
        Payout(
          id: 'ap_${alert.id}',
          reason: 'Auto payout: ${alert.title}',
          date: DateTime.now(),
          amount: amount,
        ),
      );
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  ({double score, List<String> reasons}) _assessFraudRisk({
    required RiskAlert alert,
    required double payoutAmount,
  }) {
    var score = 0.08;
    final reasons = <String>[];
    final now = DateTime.now();
    final recentPayouts = _payouts.where((p) => now.difference(p.date) <= const Duration(hours: 24)).length;

    if (_securityProfile.operatingLocation.trim().isEmpty) {
      score += 0.30;
      reasons.add('Missing verified operating location');
    }
    if (!_securityProfile.enable2Fa) {
      score += 0.14;
      reasons.add('2FA disabled on payout profile');
    }
    if ((_securityProfile.workProofId.trim()).length < 6) {
      score += 0.10;
      reasons.add('Weak work-proof identifier');
    }
    if (alert.affectedLocation.trim().toLowerCase() == 'all') {
      score += 0.18;
      reasons.add('Broad geofence trigger (all locations)');
    }
    if (recentPayouts >= 2) {
      score += 0.24;
      reasons.add('Multiple payouts within 24h window');
    }
    if (payoutAmount > (_selectedPlan.weeklyCoverage * 0.70)) {
      score += 0.20;
      reasons.add('High payout amount near weekly cap');
    }

    return (score: score.clamp(0.0, 1.0), reasons: reasons.isEmpty ? const ['No anomaly signals'] : reasons);
  }

  List<InsurancePolicy> _buildInsurancePolicies() {
    return [
      InsurancePolicy(
        id: 'policy_basic',
        name: 'Income Shield - Basic',
        description: 'Weekly income-loss protection for local disruptions',
        weeklyPremium: 299,
        coverageAmount: 50000,
        coverageDetails: ['Income loss cover up to ₹50,000 per week', 'Rain and local disruption trigger protection', 'Auto payout on approved trigger', 'Valid for 7 days'],
        type: 'basic',
      ),
      InsurancePolicy(
        id: 'policy_premium',
        name: 'Income Shield - Plus',
        description: 'Higher weekly income protection for high-risk zones',
        weeklyPremium: 599,
        coverageAmount: 100000,
        coverageDetails: ['Income loss cover up to ₹100,000 per week', 'Rain, outage, and curfew trigger protection', 'Faster auto payout priority', 'Daily trigger monitoring', 'Weekly validity (auto renewable)', '24/7 support'],
        type: 'premium',
      ),
      InsurancePolicy(
        id: 'policy_comprehensive',
        name: 'Income Shield - Max',
        description: 'Maximum weekly earnings protection for full-time riders',
        weeklyPremium: 999,
        coverageAmount: 250000,
        coverageDetails: ['Income loss cover up to ₹250,000 per week', 'All disruption triggers including severe pollution', 'Priority trigger validation window', 'Instant payout routing on approval', 'Weekly risk recalibration', 'Dedicated support'],
        type: 'comprehensive',
      ),
      InsurancePolicy(
        id: 'policy_quarterly',
        name: 'Income Shield - Smart Saver',
        description: 'Lower weekly premium for stable riding zones',
        weeklyPremium: 549,
        coverageAmount: 150000,
        coverageDetails: ['Income loss cover up to ₹150,000 per week', 'Focused weather and closure trigger cover', 'Optimized weekly pricing', 'Valid for 7 days', 'Auto-renew support'],
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
      _tabIndex = 5;
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
      premiumAmount: selected.policy.weeklyPremium,
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

  void _saveSecurityProfile(RiderSecurityProfile profile) {
    setState(() {
      _securityProfile = profile;
      _refreshLocationFilteredAlerts();
    });
    _autoProcessAlertsIfEligible();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('KYC, location, and security details saved.')),
    );
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
        securityProfile: _securityProfile,
        onSecurityProfileSaved: _saveSecurityProfile,
        onGoToAlerts: () => setState(() => _tabIndex = 3),
        onGoToInsurance: () => setState(() => _tabIndex = 2),
        onGoToPayment: () => setState(() => _tabIndex = 5),
      ),
      RiderWalletPage(planId: _selectedPlan, walletBalance: _walletBalance, payouts: _payouts, onGoToPlans: () => setState(() => _tabIndex = 2)),
      RiderCoveragePage(
        planId: _selectedPlan,
        onPlanSelected: (plan) {
          setState(() => _selectedPlan = plan);
          widget.onPlanChanged(plan);
        },
        policies: _insurancePolicies,
        selectedInsurance: _selectedInsurance,
        onPolicySelected: _handlePolicySelection,
      ),
      RiderAlertsPage(
        planId: _selectedPlan,
        alerts: _alerts,
        simulatedAlertIds: _simulatedAlertIds,
        reviewRequiredAlertIds: _reviewRequiredAlertIds,
      ),
      RiderInsightsPage(planId: _selectedPlan),
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
          BottomNavigationBarItem(icon: Icon(Icons.shield_outlined), label: 'Coverage'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_outlined), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), label: 'Insights'),
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
  final RiderSecurityProfile securityProfile;
  final ValueChanged<RiderSecurityProfile> onSecurityProfileSaved;
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
    required this.securityProfile,
    required this.onSecurityProfileSaved,
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
        RiderKycSecurityCard(
          initialProfile: securityProfile,
          accent: planId.accent,
          onSaved: onSecurityProfileSaved,
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
                const Text('Active Payout Review Windows', style: TextStyle(fontWeight: FontWeight.w900)),
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
                                    Text(riderAlertLabel(alert), style: const TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 2),
                                    Text(alertTriggerSource(alert), style: TextStyle(color: Colors.black.withOpacity(0.70), fontSize: 12, fontWeight: FontWeight.w600)),
                                    TextButton.icon(
                                      onPressed: () => openSourceLink(context, bestAlertSourcePageUrl(alert)),
                                      icon: const Icon(Icons.link, size: 16),
                                      label: const Text('Open source page'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => openSourceLink(context, bestAlertArticleUrl(alert)),
                                      icon: const Icon(Icons.open_in_new, size: 16),
                                      label: const Text('Open source'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(alertCorrectionTip(alert), style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12, fontStyle: FontStyle.italic)),
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

class RiderKycSecurityCard extends StatefulWidget {
  final RiderSecurityProfile initialProfile;
  final Color accent;
  final ValueChanged<RiderSecurityProfile> onSaved;

  const RiderKycSecurityCard({
    super.key,
    required this.initialProfile,
    required this.accent,
    required this.onSaved,
  });

  @override
  State<RiderKycSecurityCard> createState() => _RiderKycSecurityCardState();
}

class _RiderKycSecurityCardState extends State<RiderKycSecurityCard> {
  late final TextEditingController _aadhaar;
  TextEditingController? _operatingLocation;
  late final TextEditingController _workProofId;
  late final TextEditingController _upiId;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _payoutPin;
  late String _workProofType;
  late bool _enable2Fa;
  late bool _consentAccepted;
  String? _error;

  TextEditingController get _operatingLocationCtrl {
    return _operatingLocation ??= TextEditingController(text: widget.initialProfile.operatingLocation);
  }

  @override
  void initState() {
    super.initState();
    _aadhaar = TextEditingController(text: widget.initialProfile.aadhaarNumber);
    _operatingLocation = TextEditingController(text: widget.initialProfile.operatingLocation);
    _workProofId = TextEditingController(text: widget.initialProfile.workProofId);
    _upiId = TextEditingController(text: widget.initialProfile.upiId);
    _emergencyPhone = TextEditingController(text: widget.initialProfile.emergencyPhone);
    _payoutPin = TextEditingController(text: widget.initialProfile.payoutPin);
    _workProofType = widget.initialProfile.workProofType;
    _enable2Fa = widget.initialProfile.enable2Fa;
    _consentAccepted = widget.initialProfile.consentAccepted;
  }

  @override
  void dispose() {
    _aadhaar.dispose();
    _operatingLocation?.dispose();
    _workProofId.dispose();
    _upiId.dispose();
    _emergencyPhone.dispose();
    _payoutPin.dispose();
    super.dispose();
  }

  void _save() {
    final aadhaar = _aadhaar.text.trim();
    final operatingLocation = _operatingLocationCtrl.text.trim();
    final workProofId = _workProofId.text.trim();
    final upi = _upiId.text.trim();
    final emergencyPhone = _emergencyPhone.text.trim();
    final payoutPin = _payoutPin.text.trim();

    final aadhaarValid = RegExp(r'^\d{12}$').hasMatch(aadhaar);
    final upiValid = RegExp(r'^[a-zA-Z0-9._-]{2,}@[a-zA-Z]{2,}$').hasMatch(upi);
    final phoneValid = RegExp(r'^\d{10}$').hasMatch(emergencyPhone);
    final pinValid = RegExp(r'^\d{4}$').hasMatch(payoutPin);

    if (!aadhaarValid) {
      setState(() => _error = 'Aadhaar must be exactly 12 digits.');
      return;
    }
    if (operatingLocation.length < 2) {
      setState(() => _error = 'Please enter your operating location (city/zone).');
      return;
    }
    if (workProofId.isEmpty) {
      setState(() => _error = 'Work proof ID is required.');
      return;
    }
    if (!upiValid) {
      setState(() => _error = 'Enter a valid UPI ID (example: name@bank).');
      return;
    }
    if (!phoneValid) {
      setState(() => _error = 'Emergency contact must be 10 digits.');
      return;
    }
    if (!pinValid) {
      setState(() => _error = 'Payout PIN must be 4 digits.');
      return;
    }
    if (!_consentAccepted) {
      setState(() => _error = 'Please accept security and KYC consent.');
      return;
    }

    setState(() => _error = null);
    widget.onSaved(
      RiderSecurityProfile(
        aadhaarNumber: aadhaar,
        operatingLocation: operatingLocation,
        workProofType: _workProofType,
        workProofId: workProofId,
        upiId: upi,
        emergencyPhone: emergencyPhone,
        payoutPin: payoutPin,
        enable2Fa: _enable2Fa,
        consentAccepted: _consentAccepted,
        isVerified: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verified = widget.initialProfile.isVerified;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('KYC, Work Proof & Payout Security', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                Chip(
                  label: Text(verified ? 'Verified' : 'Pending'),
                  backgroundColor: (verified ? Colors.green : Colors.orange).withOpacity(0.12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Required for policy activation and secure payout processing.',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _aadhaar,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'Aadhaar Number',
                hintText: '12-digit Aadhaar',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _operatingLocationCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Operating Location',
                hintText: 'City / Area where you ride',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _workProofType,
              decoration: const InputDecoration(
                labelText: 'Work Proof Type',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.work_outline),
              ),
              items: const [
                DropdownMenuItem(value: 'Delivery ID', child: Text('Delivery ID Card')),
                DropdownMenuItem(value: 'Company Letter', child: Text('Company Letter')),
                DropdownMenuItem(value: 'Offer Letter', child: Text('Offer/Joining Letter')),
                DropdownMenuItem(value: 'Platform Screenshot', child: Text('Platform App Profile Screenshot')),
              ],
              onChanged: (value) => setState(() => _workProofType = value ?? 'Delivery ID'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _workProofId,
              decoration: const InputDecoration(
                labelText: 'Work Proof ID / Reference',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _upiId,
              decoration: const InputDecoration(
                labelText: 'UPI ID',
                hintText: 'name@bank',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyPhone,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Emergency Contact Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _payoutPin,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: '4-digit Payout Security PIN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enable2Fa,
              onChanged: (value) => setState(() => _enable2Fa = value),
              title: const Text('Enable 2FA for payout actions'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consentAccepted,
              onChanged: (value) => setState(() => _consentAccepted = value ?? false),
              title: const Text('I confirm details are valid and consent to KYC verification.'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: widget.accent),
                onPressed: _save,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Save KYC & Security Details'),
              ),
            ),
          ],
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

class RiderCoveragePage extends StatefulWidget {
  final PlanId planId;
  final ValueChanged<PlanId> onPlanSelected;
  final List<InsurancePolicy> policies;
  final SelectedInsurance? selectedInsurance;
  final ValueChanged<InsurancePolicy> onPolicySelected;

  const RiderCoveragePage({
    super.key,
    required this.planId,
    required this.onPlanSelected,
    required this.policies,
    required this.selectedInsurance,
    required this.onPolicySelected,
  });

  @override
  State<RiderCoveragePage> createState() => _RiderCoveragePageState();
}

class _RiderCoveragePageState extends State<RiderCoveragePage> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.auto_graph_outlined), label: Text('Risk Plans')),
              ButtonSegment(value: 1, icon: Icon(Icons.security_outlined), label: Text('Insurance')),
            ],
            selected: {_section},
            onSelectionChanged: (value) => setState(() => _section = value.first),
          ),
        ),
        Expanded(
          child: _section == 0
              ? RiderPricingPage(planId: widget.planId, onPlanSelected: widget.onPlanSelected)
              : InsurancePolicyPage(
                  policies: widget.policies,
                  selectedInsurance: widget.selectedInsurance,
                  onPolicySelected: widget.onPolicySelected,
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
  final Set<String> reviewRequiredAlertIds;
  final ValueChanged<RiskAlert>? onSimulatePayout;

  const RiderAlertsPage({
    super.key,
    required this.planId,
    required this.alerts,
    required this.simulatedAlertIds,
    required this.reviewRequiredAlertIds,
    this.onSimulatePayout,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Payout Status Alerts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Your account is monitored for validated payout conditions.', style: TextStyle(color: Colors.black.withOpacity(0.65))),
        const SizedBox(height: 12),
        if (alerts.isNotEmpty)
          _LossSimulatorCard(planId: planId, alerts: alerts)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text('No approved trigger alerts for your location yet. Save your operating location in KYC and wait for admin-approved events in your area.', style: TextStyle(color: Colors.black.withOpacity(0.65))),
            ),
          ),
        const SizedBox(height: 12),
        ...alerts.map((alert) {
          final simulated = simulatedAlertIds.contains(alert.id);
          final underReview = reviewRequiredAlertIds.contains(alert.id);
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
                        Expanded(child: Text(riderAlertLabel(alert), style: const TextStyle(fontWeight: FontWeight.w900))),
                        Chip(label: Text(alert.severity.name.toUpperCase())),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(alertTriggerSource(alert), style: TextStyle(color: Colors.black.withOpacity(0.70), fontSize: 12, fontWeight: FontWeight.w600)),
                    TextButton.icon(
                      onPressed: () => openSourceLink(context, bestAlertSourcePageUrl(alert)),
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Open source page'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => openSourceLink(context, bestAlertArticleUrl(alert)),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open source'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      underReview
                          ? 'Status: Held for fraud review before payout.'
                          : (simulated ? 'Status: Auto payout completed.' : 'Status: Awaiting auto payout processing.'),
                    ),
                    const SizedBox(height: 6),
                    Text('Created: ${formatDate(alert.createdAt)}'),
                    const SizedBox(height: 4),
                    Text('How to verify/correct: ${alertCorrectionTip(alert)}', style: TextStyle(color: Colors.black.withOpacity(0.58), fontSize: 12, fontStyle: FontStyle.italic)),
                    Text('Potential payout: ${inrAmt(payout)}', style: TextStyle(fontWeight: FontWeight.w900, color: planId.accent)),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(
                        underReview
                            ? 'Fraud review'
                            : (simulated ? 'Auto paid' : 'Queued'),
                      ),
                    ),
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
            const Text('Payout estimator', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Estimate possible payout using your current earnings input.', style: TextStyle(color: Colors.black.withOpacity(0.65))),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedIndex,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Select alert window'),
              items: List.generate(widget.alerts.length, (index) => DropdownMenuItem(value: index, child: Text(riderAlertLabel(widget.alerts[index])))),
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
  final List<NewsTriggerCandidate>? pendingNewsTriggers;
  final List<RiskAlert>? approvedAlerts;
  final List<FraudFlag>? fraudFlags;
  final bool? isFetchingNewsTriggers;
  final Future<void> Function() onFetchNewsTriggers;
  final void Function(String triggerId, String affectedLocation) onApproveNewsTrigger;
  final ValueChanged<String> onRejectNewsTrigger;

  const AdminHome({
    super.key,
    required this.user,
    required this.planIdHint,
    this.pendingNewsTriggers,
    this.approvedAlerts,
    this.fraudFlags,
    this.isFetchingNewsTriggers,
    required this.onFetchNewsTriggers,
    required this.onApproveNewsTrigger,
    required this.onRejectNewsTrigger,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final pending = pendingNewsTriggers ?? const <NewsTriggerCandidate>[];
    final approved = approvedAlerts ?? const <RiskAlert>[];
    final fraudFlagsData = fraudFlags ?? const <FraudFlag>[];
    final payouts = _buildAuditPayouts(planIdHint, approved);
    final analytics = _buildAnalytics(pending, approved, fraudFlagsData);

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
          _section('Intelligent analytics', _AdminAnalyticsCard(metrics: analytics, accent: planIdHint.accent)),
          _section(
            'News Trigger Intake (Uncontrollable Conditions Only)',
            _AdminNewsTriggerQueueCard(
              pendingNewsTriggers: pending,
              isFetching: isFetchingNewsTriggers ?? false,
              onFetch: onFetchNewsTriggers,
              onApprove: onApproveNewsTrigger,
              onReject: onRejectNewsTrigger,
            ),
          ),
          _section('Fraud detection', _FraudFlagsCard(flags: fraudFlagsData)),
          _section('Approved trigger feed (rider-visible)', _TriggerFeedCard(alerts: approved)),
          _section('Payout audit', _PayoutAuditCard(payouts: payouts, accent: planIdHint.accent)),
        ],
      ),
    );
  }

  AdminAnalyticsSnapshot _buildAnalytics(
    List<NewsTriggerCandidate> pending,
    List<RiskAlert> approved,
    List<FraudFlag> flags,
  ) {
    final critical = flags.where((f) => f.score >= 0.72).length;
    final warning = flags.where((f) => f.score >= 0.45 && f.score < 0.72).length;
    final highSeverity = approved.where((a) => a.severity == Severity.high).length;
    final sourceCount = approved.map((a) => a.source).toSet().length;
    final exposure = approved.fold<double>(0, (sum, alert) => sum + computePotentialPayout(planId: planIdHint, alert: alert));

    final locationDistribution = <String, int>{};
    for (final alert in approved) {
      final location = alert.affectedLocation.trim().isEmpty ? 'all' : alert.affectedLocation.trim();
      locationDistribution[location] = (locationDistribution[location] ?? 0) + 1;
    }

    return AdminAnalyticsSnapshot(
      pendingTriggers: pending.length,
      approvedTriggers: approved.length,
      criticalFraudFlags: critical,
      warningFraudFlags: warning,
      highSeverityTriggers: highSeverity,
      sourceCount: sourceCount,
      estimatedWeeklyExposure: exposure,
      locationDistribution: locationDistribution,
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

  List<Payout> _buildAuditPayouts(PlanId planId, List<RiskAlert> approved) {
    if (approved.isEmpty) return const [];
    final now = DateTime.now();
    return [
      ...approved.take(2).toList().asMap().entries.map(
        (entry) => Payout(
          id: 'pa${entry.key + 1}',
          reason: entry.value.title,
          date: now.subtract(Duration(days: entry.key + 1)),
          amount: computePotentialPayout(planId: planId, alert: entry.value),
        ),
      ),
    ];
  }
}

class _AdminNewsTriggerQueueCard extends StatelessWidget {
  final List<NewsTriggerCandidate> pendingNewsTriggers;
  final bool? isFetching;
  final Future<void> Function() onFetch;
  final void Function(String triggerId, String affectedLocation) onApprove;
  final ValueChanged<String> onReject;

  const _AdminNewsTriggerQueueCard({
    required this.pendingNewsTriggers,
    this.isFetching,
    required this.onFetch,
    required this.onApprove,
    required this.onReject,
  });

  String _categoryText(TriggerCategory category) {
    return switch (category) {
      TriggerCategory.appDowntime => 'App downtime',
      TriggerCategory.rainfall => 'Rainfall',
      TriggerCategory.extremeHeat => 'Extreme heat',
      TriggerCategory.pollution => 'Severe pollution',
      TriggerCategory.war => 'War',
      TriggerCategory.lockdown => 'Lockdown',
    };
  }

  Future<String?> _promptAffectedLocation(BuildContext context, NewsTriggerCandidate candidate) async {
    final locationController = TextEditingController(text: candidate.suggestedLocation == 'all' ? '' : candidate.suggestedLocation);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Affected location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the area where riders are actually affected. Leave blank to target all locations.'),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'City / Area / Zone',
                  hintText: 'Example: Bengaluru, Koramangala',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = locationController.text.trim();
                Navigator.of(dialogContext).pop(value.isEmpty ? 'all' : value);
              },
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    locationController.dispose();
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final fetching = isFetching ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Fetch source is restricted to uncontrollable conditions only: App downtime, Rainfall, Extreme heat, Severe pollution, War, and Lockdown/Curfew. Sources include weather/AQI APIs and simulated platform/civic feeds. Admin approval is required before riders can see them.',
                    style: TextStyle(color: Colors.black.withOpacity(0.7)),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: fetching ? null : () => onFetch(),
                  icon: fetching
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Icon(Icons.public_outlined),
                  label: Text(fetching ? 'Fetching...' : 'Fetch uncontrollable triggers'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (pendingNewsTriggers.isEmpty)
              const Text('No pending triggers. Fetch latest news to review new events.')
            else
              ...pendingNewsTriggers.take(10).map(
                    (candidate) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black.withOpacity(0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(candidate.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                                Chip(label: Text(_categoryText(candidate.category))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(candidate.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('Source: ${candidate.source} • ${formatDate(candidate.publishedAt)}', style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12)),
                            Text('Suggested impact location: ${candidate.suggestedLocation}', style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12)),
                            TextButton.icon(
                              onPressed: () => openSourceLink(context, bestCandidateSourcePageUrl(candidate)),
                              icon: const Icon(Icons.link, size: 16),
                              label: const Text('Open source page'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => openSourceLink(context, bestCandidateArticleUrl(candidate)),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Open source'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(onPressed: () => onReject(candidate.id), icon: const Icon(Icons.close), label: const Text('Reject')),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: () async {
                                    final affectedLocation = await _promptAffectedLocation(context, candidate);
                                    if (affectedLocation == null) return;
                                    onApprove(candidate.id, affectedLocation);
                                  },
                                  icon: const Icon(Icons.check),
                                  label: const Text('Approve for riders'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
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
  final List<FraudFlag>? flags;

  const _FraudFlagsCard({required this.flags});

  @override
  Widget build(BuildContext context) {
    final safeFlags = flags ?? const <FraudFlag>[];
    final sorted = [...safeFlags]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final critical = sorted.where((f) => f.score >= 0.72).length;
    final medium = sorted.where((f) => f.score >= 0.45 && f.score < 0.72).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total flags: ${sorted.length} • Critical: $critical • Medium: $medium', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              Text('No fraud anomalies flagged yet. Auto payouts are running with current risk checks.', style: TextStyle(color: Colors.black.withOpacity(0.65)))
            else
              ...sorted.take(8).map(
                (flag) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(flag.riderEmail, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('Score: ${(flag.score * 100).toStringAsFixed(0)}%'),
                      Text('Reason: ${flag.reasons.join(', ')}', style: TextStyle(color: Colors.black.withOpacity(0.75), fontSize: 12)),
                      Text('Created: ${formatDate(flag.createdAt)}', style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12)),
                    ],
                  ),
                ),
              )
          ],
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
          children: alerts.isEmpty
              ? const [Text('No approved triggers yet. Approve items from the news queue above to send them to riders.')]
              : alerts
                    .map(
                      (alert) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(alert.triggerDescription),
                            const SizedBox(height: 4),
                            Text(
                              alertTriggerSource(alert),
                              style: TextStyle(color: Colors.black.withOpacity(0.65), fontSize: 12),
                            ),
                            TextButton.icon(
                              onPressed: () => openSourceLink(context, bestAlertSourcePageUrl(alert)),
                              icon: const Icon(Icons.link, size: 16),
                              label: const Text('Open source page'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => openSourceLink(context, bestAlertArticleUrl(alert)),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Open source'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                              ),
                            ),
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
        const Text('Weekly Income Protection Policies', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Select a weekly income-loss policy for external disruption protection', style: TextStyle(color: Colors.black.withOpacity(0.65))),
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
                  Text('Validity: ${formatDate(selectedInsurance!.startDate)} to ${formatDate(selectedInsurance!.startDate.add(const Duration(days: 7)))}', style: TextStyle(color: Colors.black.withOpacity(0.6))),
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
                            Text('Weekly premium: ${inrAmt(policy.weeklyPremium)}/week', style: const TextStyle(fontWeight: FontWeight.w700)),
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
            Text('Select a weekly income protection policy first', style: TextStyle(color: Colors.black.withOpacity(0.6))),
          ],
        ),
      );
    }

    final policyColor = _getPolicyColor(policy.type);
    final gstAmount = (policy.weeklyPremium * 0.18);
    final totalAmount = policy.weeklyPremium + gstAmount;
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
                _priceRow('Weekly Premium', inrAmt(policy.weeklyPremium), policyColor),
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
                _detailRow('Validity', '7 days from activation'),
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
    final gstAmount = policy.weeklyPremium * 0.18;

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

class _AdminAnalyticsCard extends StatelessWidget {
  final AdminAnalyticsSnapshot metrics;
  final Color accent;

  const _AdminAnalyticsCard({required this.metrics, required this.accent});

  @override
  Widget build(BuildContext context) {
    final fraudTotal = metrics.criticalFraudFlags + metrics.warningFraudFlags;
    final fraudPressure = metrics.approvedTriggers == 0 ? 0.0 : (fraudTotal / metrics.approvedTriggers).clamp(0.0, 1.0);
    final topLocations = metrics.locationDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _metricChip('Pending triggers', '${metrics.pendingTriggers}'),
                _metricChip('Approved triggers', '${metrics.approvedTriggers}'),
                _metricChip('High severity', '${metrics.highSeverityTriggers}'),
                _metricChip('Data sources', '${metrics.sourceCount}'),
              ],
            ),
            const SizedBox(height: 12),
            Text('Estimated weekly exposure: ${inrAmt(metrics.estimatedWeeklyExposure)}', style: TextStyle(color: accent, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Fraud pressure index ${(fraudPressure * 100).toStringAsFixed(0)}% (critical ${metrics.criticalFraudFlags}, warning ${metrics.warningFraudFlags})'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: fraudPressure, minHeight: 8, color: fraudPressure > 0.45 ? Colors.red : accent),
            const SizedBox(height: 12),
            Text('Location distribution', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.8))),
            const SizedBox(height: 6),
            if (topLocations.isEmpty)
              Text('No approved trigger locations yet.', style: TextStyle(color: Colors.black.withOpacity(0.65)))
            else
              ...topLocations.take(4).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${entry.key}: ${entry.value} trigger(s)'),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Chip(label: Text('$label: $value'));
  }
}