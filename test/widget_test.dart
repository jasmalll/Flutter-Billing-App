import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:billing/main.dart';
import 'package:billing/models/calculation_model.dart';
import 'package:billing/models/other_models.dart';
import 'package:billing/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settlement balances deduct allowances from the selected source', () {
    final settlement = EventSettlement(
      eventDate: '2026-10-14',
      originalOtherExpenses: 500,
      originalSettingBill: 300,
      allowances: const [
        StaffAllowance(id: '1', staffName: 'Nihal', role: 'sp', basePay: 450, amount: 100, sourceCategory: 'Other Expenses', auditTag: 'Reporting charge'),
        StaffAllowance(id: '2', staffName: 'Akhil', role: 'cp', basePay: 430, amount: 50, sourceCategory: 'Setting Bill', auditTag: 'Setup'),
      ],
    );
    expect(settlement.remainingOther, 400);
    expect(settlement.remainingSetting, 250);
    expect(settlement.totalDisbursed, 1030);
  });

  test('phone normalization treats Indian country code and local number equally', () {
    expect(StorageService.normalizePhone('+91 98765-43210'), '9876543210');
    expect(StorageService.normalizePhone('09876543210'), '9876543210');
  });

  test('master wage lookup requires both normalized name and phone', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.saveMasterStaff({
      'name': 'Nihal Kumar',
      'phone': '+91 98765-43210',
      'defaultWage': 460,
      'category': 'BOY',
    });
    expect((await StorageService.findExactMasterStaff('  Nihal   Kumar ', '09876543210'))?['defaultWage'], 460);
    expect(await StorageService.findExactMasterStaff('Nihal Kumar', ''), isNull);
    expect(await StorageService.findExactMasterStaff('Nihal Kumar', '9876500000'), isNull);
  });

  test('inventory state serializes master items and counter allocations', () {
    final state = InventoryState(
      masterItems: [InventoryItem(id: 'dish', name: 'Dish', totalQuantity: 25)],
      stations: [CounterStation(id: 'c1', name: 'Counter 1', allocations: [StationAllocation(itemId: 'dish', itemName: 'Dish', quantity: 10)])],
    );
    final restored = InventoryState.fromJson(state.toJson());
    expect(restored.masterItems.single.totalQuantity, 25);
    expect(restored.stations.single.allocations.single.quantity, 10);
  });

  test('legacy bill-only backup and v2 full backup are both accepted', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StorageService.restoreBackupJson('[]'), isTrue);
    expect(await StorageService.restoreBackupJson('{"schemaVersion":2,"bills":[],"settlements":[],"masterStaff":[]}'), isTrue);
  });

  test('corrupt full backup is rejected before changing saved records', () async {
    SharedPreferences.setMockInitialValues({});
    const validBill = '{"id":"existing","auditoriumName":"Hall","date":"2026-10-14T00:00:00.000","staffList":[],"groupGpay":{}}';
    expect(await StorageService.restoreBackupJson('[$validBill]'), isTrue);
    final before = jsonDecode(await StorageService.exportBackupJson()) as Map<String, dynamic>;

    const invalidBackup = '{"schemaVersion":2,"bills":["not valid json"],"settlements":[],"masterStaff":[]}';
    expect(await StorageService.restoreBackupJson(invalidBackup), isFalse);
    final after = jsonDecode(await StorageService.exportBackupJson()) as Map<String, dynamic>;
    // exportedAt is generated on every export, so compare the saved records only.
    expect(after..remove('exportedAt'), before..remove('exportedAt'));
  });

  testWidgets('app shows the four main sections', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const StaffBillingApp());
    await tester.pumpAndSettle();
    expect(find.text('Reporting'), findsAtLeastNWidgets(1));
    expect(find.text('Outing'), findsAtLeastNWidgets(1));
    expect(find.text('Calendar'), findsAtLeastNWidgets(1));
    expect(find.text('Staff'), findsAtLeastNWidgets(1));
  });
}
