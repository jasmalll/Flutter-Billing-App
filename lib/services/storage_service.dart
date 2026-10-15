import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/catering_bill.dart';
import '../models/other_models.dart';
import '../models/calculation_model.dart';
import 'supabase_service.dart';

class StorageService {
  /// Emits whenever a restore replaces local app data; mounted screens reload from storage.
  static final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

  static void _notifyDataRestored() => dataRevision.value++;

  static const String _billsKey = 'saved_catering_bills_store';
  static const String _activeBillIdKey = 'active_catering_bill_id';
  static const String _inventoryKey = 'other_master_counts';
  static const String _settlementsKey = 'other_calculations';
  static const String _masterStaffKey = 'master_staff_directory';
  static const String _pendingCloudSyncKey = 'pending_cloud_sync_v1';
  static bool _isFlushingCloudQueue = false;
  static Timer? _cloudRetryTimer;


  static Future<InventoryState> getInventoryState() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_inventoryKey);
    if (source == null || source.isEmpty) {
      return InventoryState(stations: [
        CounterStation(id: 'counter-1', name: 'Counter 1'),
        CounterStation(id: 'vip-counter', name: 'VIP Counter'),
      ]);
    }
    try {
      return InventoryState.fromJson(source);
    } catch (_) {
      return InventoryState(stations: [
        CounterStation(id: 'counter-1', name: 'Counter 1'),
        CounterStation(id: 'vip-counter', name: 'VIP Counter'),
      ]);
    }
  }

  static Future<void> saveInventoryState(InventoryState state) async {
    final prefs = await SharedPreferences.getInstance();
    state.updatedAt = DateTime.now();
    await prefs.setString(_inventoryKey, state.toJson());
    await _enqueueCloudSync('inventory', 'inventory', state.toMap());
  }

  static Future<void> mergeCloudBill(CateringBill cloudBill) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_billsKey) ?? [];
    final index = values.indexWhere((v) {
      final local = CateringBill.fromJson(v);
      // The cloud schema has one bill per organization/date, so merge by either
      // local ID or event date to avoid duplicate local entries on a new device.
      return local.id == cloudBill.id || _dateKey(local.date) == _dateKey(cloudBill.date);
    });
    var cloudWon = false;
    if (index < 0) { values.insert(0, cloudBill.toJson()); cloudWon = true; }
    else {
      final local = CateringBill.fromJson(values[index]);
      if (cloudBill.updatedAt.isAfter(local.updatedAt)) { values[index] = cloudBill.toJson(); cloudWon = true; }
    }
    await prefs.setStringList(_billsKey, values);
    if (cloudWon) await _enqueueCloudSync('bill', _dateKey(cloudBill.date), cloudBill.toMap(), attemptNow: false);
  }

  static Future<void> mergeCloudInventory(InventoryState cloudState) async {
    final prefs = await SharedPreferences.getInstance();
    final localJson = prefs.getString(_inventoryKey);
    if (localJson == null) {
      await prefs.setString(_inventoryKey, cloudState.toJson());
      await _enqueueCloudSync('inventory', 'inventory', cloudState.toMap(), attemptNow: false);
      return;
    }
    try {
      final local = InventoryState.fromJson(localJson);
      if (cloudState.updatedAt.isAfter(local.updatedAt)) {
        await prefs.setString(_inventoryKey, cloudState.toJson());
        await _enqueueCloudSync('inventory', 'inventory', cloudState.toMap(), attemptNow: false);
      }
    } catch (_) {
      await prefs.setString(_inventoryKey, cloudState.toJson());
      await _enqueueCloudSync('inventory', 'inventory', cloudState.toMap(), attemptNow: false);
    }
  }

  static Future<List<EventSettlement>> getAllSettlements() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_settlementsKey) ?? [];
    return values.map((value) => EventSettlement.fromJson(value)).toList();
  }

  static Future<EventSettlement?> getSettlement(String eventDate) async {
    final all = await getAllSettlements();
    for (final item in all) {
      if (item.eventDate == eventDate) return item;
    }
    return null;
  }

  static Future<void> mergeCloudSettlement(EventSettlement cloudSettlement) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_settlementsKey) ?? [];
    final index = values.indexWhere((v) => EventSettlement.fromJson(v).eventDate == cloudSettlement.eventDate);
    var cloudWon = false;
    if (index < 0) { values.insert(0, cloudSettlement.toJson()); cloudWon = true; }
    else if (cloudSettlement.updatedAt.isAfter(EventSettlement.fromJson(values[index]).updatedAt)) {
      values[index] = cloudSettlement.toJson();
      cloudWon = true;
    }
    await prefs.setStringList(_settlementsKey, values);
    if (cloudWon) await _enqueueCloudSync('settlement', cloudSettlement.eventDate, cloudSettlement.toMap(), attemptNow: false);
  }

  static Future<void> mergeCloudMasterStaff(Map<String, dynamic> cloudStaff) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_masterStaffKey) ?? [];
    final phone = _normalizePhone(cloudStaff['phone']?.toString() ?? '');
    if (phone.isEmpty) return;
    final index = values.indexWhere((v) => _normalizePhone((jsonDecode(v) as Map)['phone']?.toString() ?? '') == phone);
    var cloudWon = false;
    if (index < 0) { values.add(jsonEncode(cloudStaff)); cloudWon = true; }
    else {
      final local = Map<String, dynamic>.from(jsonDecode(values[index]) as Map);
      final localUpdated = DateTime.tryParse(local['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cloudUpdated = DateTime.tryParse(cloudStaff['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (cloudUpdated.isAfter(localUpdated)) { values[index] = jsonEncode(cloudStaff); cloudWon = true; }
    }
    await prefs.setStringList(_masterStaffKey, values);
    if (cloudWon) await _enqueueCloudSync('staff', _normalizePhone(cloudStaff['phone']?.toString() ?? ''), cloudStaff, attemptNow: false);
  }

  static Future<void> saveSettlement(EventSettlement settlement) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_settlementsKey) ?? [];
    final index = values.indexWhere((value) => EventSettlement.fromJson(value).eventDate == settlement.eventDate);
    if (index >= 0) {
      values[index] = settlement.toJson();
    } else {
      values.insert(0, settlement.toJson());
    }
    settlement.updatedAt = DateTime.now();
    // Re-write after updating the modification timestamp.
    final refreshedIndex = values.indexWhere((value) => EventSettlement.fromJson(value).eventDate == settlement.eventDate);
    if (refreshedIndex >= 0) values[refreshedIndex] = settlement.toJson();
    await prefs.setStringList(_settlementsKey, values);
    await _enqueueCloudSync('settlement', settlement.eventDate, settlement.toMap());
  }

  static Future<List<Map<String, dynamic>>> getMasterStaffDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_masterStaffKey) ?? [];
    return values.map((value) => Map<String, dynamic>.from(jsonDecode(value) as Map)).toList();
  }

  static Future<void> saveMasterStaff(Map<String, dynamic> staff) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_masterStaffKey) ?? [];
    final phone = _normalizePhone(staff['phone']?.toString() ?? '');
    if (phone.isEmpty) throw ArgumentError('A phone number is required for the master staff directory.');
    final normalized = <String, dynamic>{
      ...staff,
      'phone': phone,
      'name': staff['name']?.toString().trim() ?? '',
      'defaultWage': (staff['defaultWage'] as num?)?.toDouble() ?? 430.0,
      'category': staff['category']?.toString() ?? 'BOY',
      'updatedAt': DateTime.now().toIso8601String(),
    };
    final index = values.indexWhere((value) => _normalizePhone((jsonDecode(value) as Map)['phone']?.toString() ?? '') == phone);
    if (index >= 0) {
      values[index] = jsonEncode(normalized);
    } else {
      values.add(jsonEncode(normalized));
    }
    await prefs.setStringList(_masterStaffKey, values);
    await _enqueueCloudSync('staff', phone, normalized);
  }

  static Future<void> deleteMasterStaff(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_masterStaffKey) ?? [];
    final normalized = _normalizePhone(phone);
    values.removeWhere((value) => _normalizePhone((jsonDecode(value) as Map)['phone']?.toString() ?? '') == normalized);
    await prefs.setStringList(_masterStaffKey, values);
    await _enqueueCloudSync('delete_staff', normalized, {'phone': normalized});
  }

  static String normalizePhone(String value) => _normalizePhone(value);

  static String _normalizePhone(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    // Treat Indian country code and a local 10-digit number as equivalent.
    if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);
    if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  static Future<Map<String, dynamic>?> findExactMasterStaff(String name, String phone) async {
    final normalizedPhone = _normalizePhone(phone);
    if (normalizedPhone.isEmpty || name.trim().isEmpty) return null;
    final directory = await getMasterStaffDirectory();
    final normalizedName = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final staff in directory) {
      final savedPhone = _normalizePhone(staff['phone']?.toString() ?? '');
      final savedName = (staff['name']?.toString() ?? '')
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');
      if (savedPhone == normalizedPhone && savedName == normalizedName) return staff;
    }
    return null;
  }

  static Future<void> saveBill(CateringBill bill) async {
    bill.updatedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_billsKey) ?? [];
    int existingIdx = -1;
    for (int i = 0; i < list.length; i++) {
      if (CateringBill.fromJson(list[i]).id == bill.id) {
        existingIdx = i;
        break;
      }
    }
    if (existingIdx >= 0) {
      list[existingIdx] = bill.toJson();
    } else {
      list.insert(0, bill.toJson());
    }
    await prefs.setStringList(_billsKey, list);
    await prefs.setString(_activeBillIdKey, bill.id);
    // Durable local-first queue: the local write finishes before cloud sync starts.
    await _enqueueCloudSync('bill', _dateKey(bill.date), bill.toMap());
  }

  static Future<List<CateringBill>> getAllBills() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_billsKey) ?? [];
    return list.map((e) => CateringBill.fromJson(e)).toList();
  }

  static Future<CateringBill?> getActiveBill() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_activeBillIdKey);
    if (activeId == null) return null;
    final all = await getAllBills();
    for (var b in all) {
      if (b.id == activeId) return b;
    }
    return null;
  }

  static Future<void> deleteBill(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_billsKey) ?? [];
    final removed = list.map(CateringBill.fromJson).where((bill) => bill.id == id).toList();
    list.removeWhere((e) => CateringBill.fromJson(e).id == id);
    await prefs.setStringList(_billsKey, list);
    if (prefs.getString(_activeBillIdKey) == id) {
      await prefs.remove(_activeBillIdKey);
    }
    if (removed.isNotEmpty) {
      final eventDate = _dateKey(removed.first.date);
      // Keep local data consistent with the cloud schema's ON DELETE CASCADE.
      final settlements = prefs.getStringList(_settlementsKey) ?? [];
      settlements.removeWhere((value) => EventSettlement.fromJson(value).eventDate == eventDate);
      await prefs.setStringList(_settlementsKey, settlements);
      final queue = (prefs.getStringList(_pendingCloudSyncKey) ?? [])
          .map((value) => Map<String, dynamic>.from(jsonDecode(value) as Map))
          .toList();
      queue.removeWhere((item) => item['type'] == 'settlement' && item['key'] == eventDate);
      await prefs.setStringList(_pendingCloudSyncKey, queue.map(jsonEncode).toList());
      await _enqueueCloudSync('delete_bill', eventDate, {'eventDate': eventDate});
    }
  }

  static Future<void> clearActiveBillTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeBillIdKey);
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Queue the latest version of a record after its local write has completed.
  /// Failed cloud operations remain in SharedPreferences and survive app restarts.
  static Future<void> _enqueueCloudSync(String type, String key, Map<String, dynamic> payload, {bool attemptNow = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = (prefs.getStringList(_pendingCloudSyncKey) ?? []).map((value) => Map<String, dynamic>.from(jsonDecode(value) as Map)).toList();
    final oppositeType = switch (type) {
      'bill' => 'delete_bill',
      'delete_bill' => 'bill',
      'staff' => 'delete_staff',
      'delete_staff' => 'staff',
      _ => null,
    };
    queue.removeWhere((item) =>
        (item['type'] == type || item['type'] == oppositeType) && item['key'] == key);
    queue.add({'type': type, 'key': key, 'payload': payload, 'queuedAt': DateTime.now().toIso8601String()});
    await prefs.setStringList(_pendingCloudSyncKey, queue.map(jsonEncode).toList());
    if (attemptNow) unawaited(flushPendingCloudSync());
  }

  /// Retry pending records in dependency order. This is safe to call on startup,
  /// after sign-in, and whenever the user opens the cloud/data screen.
  static Future<void> flushPendingCloudSync() async {
    if (_isFlushingCloudQueue || !SupabaseService.isSignedIn) return;
    _isFlushingCloudQueue = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = (prefs.getStringList(_pendingCloudSyncKey) ?? []).map((value) => Map<String, dynamic>.from(jsonDecode(value) as Map)).toList();
      const priority = {'bill': 0, 'inventory': 1, 'staff': 2, 'delete_staff': 3, 'settlement': 4, 'delete_bill': 5};
      queue.sort((a, b) => (priority[a['type']] ?? 99).compareTo(priority[b['type']] ?? 99));
      for (final item in queue) {
        final type = item['type']?.toString() ?? '';
        final key = item['key']?.toString() ?? '';
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        try {
          switch (type) {
            case 'bill':
              await SupabaseService.syncBill(CateringBill.fromMap(payload));
              break;
            case 'inventory':
              await SupabaseService.syncInventory(InventoryState.fromJson(jsonEncode(payload)));
              break;
            case 'staff':
              await SupabaseService.syncMasterStaff(payload);
              break;
            case 'settlement':
              await SupabaseService.syncSettlement(EventSettlement.fromJson(jsonEncode(payload)));
              break;
            case 'delete_staff':
              await SupabaseService.deleteMasterStaff(key);
              break;
            case 'delete_bill':
              await SupabaseService.deleteBill(key);
              break;
            default:
              continue;
          }
          if (!SupabaseService.isSignedIn) {
            throw StateError('Cloud session ended before sync completion.');
          }
          // Remove only the version that succeeded; keep any newer edit queued.
          final latest = (prefs.getStringList(_pendingCloudSyncKey) ?? []).map((value) => Map<String, dynamic>.from(jsonDecode(value) as Map)).toList();
          latest.removeWhere((candidate) => candidate['type'] == type && candidate['key'] == key && jsonEncode(candidate['payload']) == jsonEncode(payload));
          await prefs.setStringList(_pendingCloudSyncKey, latest.map(jsonEncode).toList());
        } catch (_) {
          // Keep failed operation and continue other independent records.
        }
      }
    } finally {
      _isFlushingCloudQueue = false;
      unawaited(_scheduleCloudRetryIfNeeded());
    }
  }

  static Future<void> _scheduleCloudRetryIfNeeded() async {
    if (!SupabaseService.isSignedIn) return;
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getStringList(_pendingCloudSyncKey) ?? []).isEmpty) {
      _cloudRetryTimer?.cancel();
      _cloudRetryTimer = null;
      return;
    }
    _cloudRetryTimer ??= Timer(const Duration(seconds: 30), () {
      _cloudRetryTimer = null;
      unawaited(flushPendingCloudSync());
    });
  }

  static Future<int> getPendingCloudSyncCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingCloudSyncKey) ?? []).length;
  }

  static Future<String> exportBackupJson() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonEncode({
      'schemaVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'bills': prefs.getStringList(_billsKey) ?? [],
      'inventory': prefs.getString(_inventoryKey),
      'settlements': prefs.getStringList(_settlementsKey) ?? [],
      'masterStaff': prefs.getStringList(_masterStaffKey) ?? [],
    });
  }

  static Future<bool> restoreBackupJson(String jsonStr) async {
    try {
      final decoded = jsonDecode(jsonStr);
      final prefs = await SharedPreferences.getInstance();

      // Backward compatibility with the original bills-only JSON array.
      if (decoded is List) {
        final bills = decoded.map(_backupEntryToJson).toList();
        // Validate the complete archive before replacing any saved data.
        for (final bill in bills) {
          CateringBill.fromJson(bill);
        }
        await prefs.setStringList(_billsKey, bills);
        if (bills.isNotEmpty) {
          await prefs.setString(_activeBillIdKey, CateringBill.fromJson(bills.first).id);
        } else {
          await prefs.remove(_activeBillIdKey);
        }
        _notifyDataRestored();
        return true;
      }

      if (decoded is! Map || decoded['schemaVersion'] != 2 || decoded['bills'] is! List) {
        return false;
      }

      // Decode and validate every section before changing local storage. A corrupt
      // backup must not partially replace a user's existing billing records.
      final bills = (decoded['bills'] as List).map(_backupEntryToJson).toList();
      for (final bill in bills) {
        CateringBill.fromJson(bill);
      }

      final settlements = decoded['settlements'] is List
          ? (decoded['settlements'] as List).map(_backupEntryToJson).toList()
          : null;
      if (settlements != null) {
        for (final settlement in settlements) {
          EventSettlement.fromJson(settlement);
        }
      }

      final masterStaff = decoded['masterStaff'] is List
          ? (decoded['masterStaff'] as List).map(_backupEntryToJson).toList()
          : null;
      if (masterStaff != null) {
        for (final staff in masterStaff) {
          if (jsonDecode(staff) is! Map) return false;
        }
      }

      final inventoryJson = decoded['inventory'];
      if (inventoryJson != null) {
        if (inventoryJson is! String) return false;
        InventoryState.fromJson(inventoryJson);
      }

      await prefs.setStringList(_billsKey, bills);
      if (inventoryJson is String) {
        await prefs.setString(_inventoryKey, inventoryJson);
      } else if (inventoryJson == null) {
        await prefs.remove(_inventoryKey);
      }
      if (settlements != null) await prefs.setStringList(_settlementsKey, settlements);
      if (masterStaff != null) await prefs.setStringList(_masterStaffKey, masterStaff);

      // The active bill pointer can refer to data from before this restore.
      if (bills.isNotEmpty) {
        await prefs.setString(_activeBillIdKey, CateringBill.fromJson(bills.first).id);
      } else {
        await prefs.remove(_activeBillIdKey);
      }
      _notifyDataRestored();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _backupEntryToJson(dynamic value) {
    if (value is String) return value;
    if (value is Map) return jsonEncode(Map<String, dynamic>.from(value));
    throw const FormatException('Backup entries must be JSON objects or encoded JSON strings.');
  }
}