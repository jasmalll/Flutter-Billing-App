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
    unawaited(_syncInventoryBestEffort(state));
  }

  static Future<void> mergeCloudBill(CateringBill cloudBill) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_billsKey) ?? [];
    final index = values.indexWhere((v) => CateringBill.fromJson(v).id == cloudBill.id);
    if (index < 0) { values.insert(0, cloudBill.toJson()); }
    else {
      final local = CateringBill.fromJson(values[index]);
      if (cloudBill.updatedAt.isAfter(local.updatedAt)) values[index] = cloudBill.toJson();
    }
    await prefs.setStringList(_billsKey, values);
  }

  static Future<void> mergeCloudInventory(InventoryState cloudState) async {
    final prefs = await SharedPreferences.getInstance();
    final localJson = prefs.getString(_inventoryKey);
    if (localJson == null) { await prefs.setString(_inventoryKey, cloudState.toJson()); return; }
    try {
      final local = InventoryState.fromJson(localJson);
      if (cloudState.updatedAt.isAfter(local.updatedAt)) await prefs.setString(_inventoryKey, cloudState.toJson());
    } catch (_) { await prefs.setString(_inventoryKey, cloudState.toJson()); }
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
    if (index < 0) { values.insert(0, cloudSettlement.toJson()); }
    else if (cloudSettlement.updatedAt.isAfter(EventSettlement.fromJson(values[index]).updatedAt)) { values[index] = cloudSettlement.toJson(); }
    await prefs.setStringList(_settlementsKey, values);
  }

  static Future<void> mergeCloudMasterStaff(Map<String, dynamic> cloudStaff) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_masterStaffKey) ?? [];
    final phone = _normalizePhone(cloudStaff['phone']?.toString() ?? '');
    if (phone.isEmpty) return;
    final index = values.indexWhere((v) => _normalizePhone((jsonDecode(v) as Map)['phone']?.toString() ?? '') == phone);
    if (index < 0) { values.add(jsonEncode(cloudStaff)); }
    else {
      final local = Map<String, dynamic>.from(jsonDecode(values[index]) as Map);
      final localUpdated = DateTime.tryParse(local['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cloudUpdated = DateTime.tryParse(cloudStaff['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (cloudUpdated.isAfter(localUpdated)) values[index] = jsonEncode(cloudStaff);
    }
    await prefs.setStringList(_masterStaffKey, values);
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
    unawaited(_syncSettlementBestEffort(settlement));
  }

  static Future<void> _syncMasterStaffBestEffort(Map<String, dynamic> staff) async {
    try { await SupabaseService.syncMasterStaff(staff); } catch (_) { /* retained locally */ }
  }

  static Future<void> _syncInventoryBestEffort(InventoryState state) async {
    try { await SupabaseService.syncInventory(state); } catch (_) { /* stays queued locally; sync can be retried */ }
  }

  static Future<void> _syncSettlementBestEffort(EventSettlement settlement) async {
    try { await SupabaseService.syncSettlement(settlement); } catch (_) { /* stays saved locally */ }
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
    unawaited(_syncMasterStaffBestEffort(normalized));
  }

  static Future<void> deleteMasterStaff(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_masterStaffKey) ?? [];
    final normalized = _normalizePhone(phone);
    values.removeWhere((value) => _normalizePhone((jsonDecode(value) as Map)['phone']?.toString() ?? '') == normalized);
    await prefs.setStringList(_masterStaffKey, values);
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
    // Local save completes first; cloud sync is deliberately non-blocking.
    SupabaseService.queueBillSync(bill);
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
    list.removeWhere((e) => CateringBill.fromJson(e).id == id);
    await prefs.setStringList(_billsKey, list);
    if (prefs.getString(_activeBillIdKey) == id) {
      await prefs.remove(_activeBillIdKey);
    }
  }

  static Future<void> clearActiveBillTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeBillIdKey);
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