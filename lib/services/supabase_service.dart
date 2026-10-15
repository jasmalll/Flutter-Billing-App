import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/calculation_model.dart';
import '../models/catering_bill.dart';
import '../models/other_models.dart';

/// Optional cloud layer. Local storage remains the source of truth until the
/// app is configured with Supabase URL/anon key and a supervisor signs in.
class SupabaseService {
  SupabaseService._();

  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool _initialized = false;

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;
  static bool get isInitialized => _initialized;
  static bool get isSignedIn => _initialized && Supabase.instance.client.auth.currentSession != null;
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    if (!isConfigured || _initialized) return;
    await Supabase.initialize(url: _url, anonKey: _anonKey);
    _initialized = true;
  }

  static Future<AuthResponse> signIn({required String email, required String password}) async {
    _requireInitialized();
    return client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  static Future<AuthResponse> signUp({required String email, required String password}) async {
    _requireInitialized();
    return client.auth.signUp(email: email.trim(), password: password);
  }

  static Future<void> signOut() async {
    _requireInitialized();
    await client.auth.signOut();
  }

  static Future<void> syncBill(CateringBill bill) async {
    if (!isSignedIn) return;
    final user = client.auth.currentUser!;
    final orgId = user.appMetadata['org_id'];
    if (orgId == null) {
      throw StateError('Supabase user is missing org_id metadata; assign the supervisor organization before syncing.');
    }
    await client.from('event_bills').upsert({
      'event_date': _dateOnly(bill.date),
      'auditorium_name': bill.auditoriumName,
      'bill_payload': bill.toMap(),
      'grand_total': bill.getAllTotalBill(bill.taMultiplier),
      'organization_id': orgId,
      'updated_at': bill.updatedAt.toUtc().toIso8601String(),
    }, onConflict: 'organization_id,event_date');
  }

  static Future<void> syncMasterStaff(Map<String, dynamic> staff) async {
    if (!isSignedIn) return;
    final orgId = _organizationId;
    if (orgId == null) throw StateError('Supabase user is missing org_id metadata.');
    await client.from('master_staff').upsert({
      'organization_id': orgId,
      'name': staff['name']?.toString() ?? '',
      'phone': staff['phone']?.toString() ?? '',
      'default_wage': (staff['defaultWage'] as num?)?.toDouble() ?? 430.0,
      'category': staff['category']?.toString() ?? 'BOY',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'organization_id,phone');
  }

  static Future<void> syncInventory(InventoryState state) async {
    if (!isSignedIn) return;
    final orgId = _organizationId;
    if (orgId == null) throw StateError('Supabase user is missing org_id metadata.');
    await client.from('inventory_counts').upsert({
      'organization_id': orgId,
      'catalog_payload': state.toMap(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'organization_id');
  }

  static Future<void> syncSettlement(EventSettlement settlement) async {
    if (!isSignedIn) return;
    final orgId = _organizationId;
    if (orgId == null) throw StateError('Supabase user is missing org_id metadata.');
    await client.from('event_settlements').upsert({
      'event_date': settlement.eventDate,
      'organization_id': orgId,
      'settlement_payload': settlement.toMap(),
      'net_disbursed_total': settlement.totalDisbursed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'organization_id,event_date');
  }


  static Future<void> deleteMasterStaff(String phone) async {
    if (!isSignedIn) return;
    final orgId = _organizationId;
    if (orgId == null) throw StateError('Supabase user is missing org_id metadata.');
    await client.from('master_staff').delete().eq('organization_id', orgId).eq('phone', phone);
  }

  static Future<void> deleteBill(String eventDate) async {
    if (!isSignedIn) return;
    final orgId = _organizationId;
    if (orgId == null) throw StateError('Supabase user is missing org_id metadata.');
    // The schema cascades related event settlements when the event bill is removed.
    await client.from('event_bills').delete().eq('organization_id', orgId).eq('event_date', eventDate);
  }

  static Future<List<CateringBill>> fetchBills() async {
    if (!isSignedIn) return [];
    final rows = await client.from('event_bills').select('bill_payload');
    final result = <CateringBill>[];
    for (final row in rows) {
      final payload = row['bill_payload'];
      if (payload is Map) {
        try { result.add(CateringBill.fromMap(Map<String, dynamic>.from(payload))); } catch (_) {}
      }
    }
    return result;
  }

  static Future<InventoryState?> fetchInventory() async {
    if (!isSignedIn) return null;
    final row = await client.from('inventory_counts').select('catalog_payload,updated_at').limit(1).maybeSingle();
    if (row == null || row['catalog_payload'] is! Map) return null;
    final payload = Map<String, dynamic>.from(row['catalog_payload'] as Map);
    payload.putIfAbsent('updatedAt', () => row['updated_at']?.toString());
    return InventoryState.fromJson(_encodeMap(payload));
  }

  static Future<List<EventSettlement>> fetchSettlements() async {
    if (!isSignedIn) return [];
    final rows = await client.from('event_settlements').select('settlement_payload');
    final result = <EventSettlement>[];
    for (final row in rows) {
      final payload = row['settlement_payload'];
      if (payload is Map) {
        try { result.add(EventSettlement.fromJson(_encodeMap(Map<String, dynamic>.from(payload)))); } catch (_) {}
      }
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> fetchMasterStaff() async {
    if (!isSignedIn) return [];
    final rows = await client.from('master_staff').select('name,phone,default_wage,category,updated_at');
    return rows.map((row) => <String, dynamic>{
      'name': row['name'],
      'phone': row['phone'],
      'defaultWage': row['default_wage'],
      'category': row['category'],
      'updatedAt': row['updated_at'],
    }).toList();
  }

  static String _encodeMap(Map<String, dynamic> map) {
    // Avoid a dependency on a remote serializer; model factories use JSON for validation.
    return jsonEncode(map);
  }

  static dynamic get _organizationId {
    final user = client.auth.currentUser;
    return user?.appMetadata['org_id'];
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static void _requireInitialized() {
    if (!_initialized) throw StateError('Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY at build time.');
  }
}
