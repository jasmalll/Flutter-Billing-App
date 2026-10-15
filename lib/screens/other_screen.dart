import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import '../models/calculation_model.dart';
import '../models/catering_bill.dart';
import '../models/other_models.dart';
import '../services/storage_service.dart';
import '../services/calculation_pdf_service.dart';
import '../services/supabase_service.dart';

class OtherScreen extends StatefulWidget {
  final ValueChanged<CateringBill>? onOpenBill;
  const OtherScreen({super.key, this.onOpenBill});

  @override
  State<OtherScreen> createState() => _OtherScreenState();
}

class _OtherScreenState extends State<OtherScreen> {
  String _mode = 'Overview';
  bool _loading = true;
  InventoryState _inventory = InventoryState();
  List<CateringBill> _bills = [];
  List<Map<String, dynamic>> _masterStaff = [];
  String _staffFilter = 'ALL';
  final TextEditingController _staffSearchController = TextEditingController();
  String _staffSearch = '';
  DateTime _selectedDate = DateTime.now();
  EventSettlement? _settlement;
  CateringBill? _selectedBill;

  @override
  void initState() {
    super.initState();
    _initialize();
    StorageService.dataRevision.addListener(_onRestoredDataChanged);
  }

  Future<void> _initialize() async {
    if (SupabaseService.isSignedIn) await _syncLocalDataToCloud();
    final results = await Future.wait([
      StorageService.getInventoryState(),
      StorageService.getAllBills(),
      StorageService.getMasterStaffDirectory(),
    ]);
    if (!mounted) return;
    setState(() {
      _inventory = results[0] as InventoryState;
      _bills = results[1] as List<CateringBill>;
      _masterStaff = results[2] as List<Map<String, dynamic>>;
      _loading = false;
    });
    await _loadSettlementForDate(_selectedDate);
  }

  void _onRestoredDataChanged() {
    _reloadAfterRestore();
  }

  Future<void> _reloadAfterRestore() async {
    final results = await Future.wait([
      StorageService.getInventoryState(),
      StorageService.getAllBills(),
      StorageService.getMasterStaffDirectory(),
    ]);
    if (!mounted) return;
    setState(() {
      _inventory = results[0] as InventoryState;
      _bills = results[1] as List<CateringBill>;
      _masterStaff = results[2] as List<Map<String, dynamic>>;
    });
    await _loadSettlementForDate(_selectedDate);
  }

  @override
  void dispose() {
    StorageService.dataRevision.removeListener(_onRestoredDataChanged);
    _staffSearchController.dispose();
    super.dispose();
  }

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  String _money(num value) => '₹${NumberFormat('#,##,##0.##').format(value)}';

  Future<void> _loadSettlementForDate(DateTime date) async {
    final key = _dateKey(date);
    final bill = _bills.where((b) => _dateKey(b.date) == key).firstOrNull;
    var settlement = await StorageService.getSettlement(key);
    if (settlement == null) {
      settlement = EventSettlement(
        eventDate: key,
        auditoriumName: bill?.auditoriumName ?? '',
        originalOtherExpenses: bill?.otherExpenses ?? 0,
        originalSettingBill: bill?.settingExpenses ?? 0,
        allowances: (bill?.spList ?? []).followedBy(bill?.cpList ?? []).map((staff) {
          return StaffAllowance(
            id: '${staff.role}-${staff.index}-${staff.phone}-${staff.name}',
            staffName: staff.name,
            role: staff.role,
            basePay: staff.getEffectiveWage(),
            amount: 0,
            sourceCategory: 'Other Expenses',
            auditTag: '',
          );
        }).toList(),
      );
    }
    if (!mounted) return;
    setState(() {
      _selectedDate = date;
      _selectedBill = bill;
      _settlement = settlement;
    });
  }

  Future<void> _saveInventory() async => StorageService.saveInventoryState(_inventory);

  Future<void> _addMasterStaff() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final wageCtrl = TextEditingController(text: '430');
    var category = 'BOY';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: const Text('Add manpower'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
        TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number (required)')),
        TextField(controller: wageCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Default wage (₹)')),
        DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Category'), items: const [DropdownMenuItem(value: 'BOY', child: Text('Boy')), DropdownMenuItem(value: 'SP', child: Text('SP')), DropdownMenuItem(value: 'CP', child: Text('CP'))], onChanged: (v) { if (v != null) setDialogState(() => category = v); }),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save staff'))],
    )));
    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final wage = double.tryParse(wageCtrl.text.trim()) ?? 430;
    nameCtrl.dispose(); phoneCtrl.dispose(); wageCtrl.dispose();
    if (ok != true || name.isEmpty || phone.isEmpty || wage < 0) return;
    try {
      await StorageService.saveMasterStaff({'name': name, 'phone': phone, 'defaultWage': wage, 'category': category});
      final directory = await StorageService.getMasterStaffDirectory();
      if (mounted) setState(() => _masterStaff = directory);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manpower saved locally. Cloud sync runs when configured and signed in.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save staff: $error')));
    }
  }

  Future<void> _editMasterStaff(Map<String, dynamic> staff) async {
    final nameCtrl = TextEditingController(text: staff['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: staff['phone']?.toString() ?? '');
    final wageCtrl = TextEditingController(text: (staff['defaultWage'] as num? ?? 430).toString());
    var category = staff['category']?.toString() ?? 'BOY';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: const Text('Edit manpower'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
        TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
        TextField(controller: wageCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Default wage (₹)')),
        DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Category'), items: const [DropdownMenuItem(value: 'SP', child: Text('SP')), DropdownMenuItem(value: 'CP', child: Text('CP')), DropdownMenuItem(value: 'BOY', child: Text('Boy'))], onChanged: (v) { if (v != null) setDialogState(() => category = v); }),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
    )));
    final name = nameCtrl.text.trim(); final phone = phoneCtrl.text.trim(); final wage = double.tryParse(wageCtrl.text.trim());
    nameCtrl.dispose(); phoneCtrl.dispose(); wageCtrl.dispose();
    if (ok != true || name.isEmpty || phone.isEmpty || wage == null || wage < 0) return;
    try {
      if (phone != (staff['phone']?.toString() ?? '')) await StorageService.deleteMasterStaff(staff['phone']?.toString() ?? '');
      await StorageService.saveMasterStaff({'name': name, 'phone': phone, 'defaultWage': wage, 'category': category});
      if (!mounted) return;
      setState(() {});
      await _initialize();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update manpower: $e'))); }
  }

  Future<void> _deleteMasterStaff(Map<String, dynamic> staff) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete manpower?'),
      content: Text('Remove ${staff['name']} from the directory? Existing bills will not be changed.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))],
    ));
    if (ok != true) return;
    await StorageService.deleteMasterStaff(staff['phone']?.toString() ?? '');
    await _initialize();
  }

  Future<void> _showCloudAuthDialog() async {
    if (!SupabaseService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supabase is not configured. Build with SUPABASE_URL and SUPABASE_ANON_KEY dart-defines first.')));
      return;
    }
    if (SupabaseService.isSignedIn) {
      await SupabaseService.signOut();
      if (mounted) setState(() {});
      return;
    }
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Supervisor sign in'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign in'))],
    ));
    final email = emailCtrl.text.trim(); final password = passwordCtrl.text;
    emailCtrl.dispose(); passwordCtrl.dispose();
    if (ok != true) return;
    try {
      await SupabaseService.signIn(email: email, password: password);
      await _initialize();
      if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed in. Local data sync attempted.'))); }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cloud sign-in/sync failed: $error')));
    }
  }

  Future<void> _syncLocalDataToCloud() async {
    if (!SupabaseService.isSignedIn) return;
    // Pull first so a fresh device can recover cloud records before pushing its defaults.
    try {
      for (final bill in await SupabaseService.fetchBills()) {
        await StorageService.mergeCloudBill(bill);
      }
    } catch (_) { /* keep local data if the cloud archive cannot be read */ }
    try {
      final cloudInventory = await SupabaseService.fetchInventory();
      if (cloudInventory != null) await StorageService.mergeCloudInventory(cloudInventory);
    } catch (_) {}
    try {
      for (final settlement in await SupabaseService.fetchSettlements()) {
        await StorageService.mergeCloudSettlement(settlement);
      }
    } catch (_) {}
    try {
      for (final staff in await SupabaseService.fetchMasterStaff()) {
        await StorageService.mergeCloudMasterStaff(staff);
      }
    } catch (_) {}

    final latestByDate = <String, CateringBill>{};
    for (final bill in await StorageService.getAllBills()) {
      final key = _dateKey(bill.date);
      final previous = latestByDate[key];
      if (previous == null || bill.updatedAt.isAfter(previous.updatedAt)) latestByDate[key] = bill;
    }
    for (final bill in latestByDate.values) {
      try { await SupabaseService.syncBill(bill); } catch (_) { /* local copy remains intact */ }
    }
    try { await SupabaseService.syncInventory(await StorageService.getInventoryState()); } catch (_) {}
    for (final settlement in await StorageService.getAllSettlements()) {
      try { await SupabaseService.syncSettlement(settlement); } catch (_) {}
    }
    for (final staff in await StorageService.getMasterStaffDirectory()) {
      try { await SupabaseService.syncMasterStaff(staff); } catch (_) {}
    }
    // Flush durable writes that previously failed or were made while offline/signed out.
    await StorageService.flushPendingCloudSync();
  }

  Future<void> _addMasterItem() async {
    final nameCtrl = TextEditingController();
    final countCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add master inventory item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Item name')),
          TextField(controller: countCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total quantity')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))],
      ),
    );
    final name = nameCtrl.text.trim();
    final quantity = int.tryParse(countCtrl.text.trim()) ?? 0;
    nameCtrl.dispose();
    countCtrl.dispose();
    if (ok != true || name.isEmpty || quantity < 0) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _inventory.masterItems.add(InventoryItem(id: id, name: name, totalQuantity: quantity));
      for (final station in _inventory.stations) {
        station.allocations.add(StationAllocation(itemId: id, itemName: name, quantity: 0));
      }
    });
    await _saveInventory();
  }

  Future<void> _editMasterItem(InventoryItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final countCtrl = TextEditingController(text: item.totalQuantity.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit master item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item name')),
          TextField(controller: countCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total quantity')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      ),
    );
    final name = nameCtrl.text.trim();
    final quantity = int.tryParse(countCtrl.text.trim());
    nameCtrl.dispose();
    countCtrl.dispose();
    if (ok != true || name.isEmpty || quantity == null || quantity < 0) return;
    setState(() {
      item.name = name;
      item.totalQuantity = quantity;
      for (final station in _inventory.stations) {
        for (final allocation in station.allocations.where((a) => a.itemId == item.id && !a.isCustom)) {
          allocation.itemName = name;
        }
      }
    });
    await _saveInventory();
  }

  Future<void> _deleteMasterItem(InventoryItem item) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete inventory item?'),
      content: Text('Remove "${item.name}" from the master catalog and all station templates?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))],
    ));
    if (ok != true) return;
    setState(() {
      _inventory.masterItems.removeWhere((i) => i.id == item.id);
      for (final station in _inventory.stations) {
        station.allocations.removeWhere((a) => a.itemId == item.id && !a.isCustom);
      }
    });
    await _saveInventory();
  }

  Future<void> _addStation() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New counter station'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Counter name')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))],
    ));
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty) return;
    setState(() => _inventory.stations.add(CounterStation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      allocations: _inventory.masterItems.map((item) => StationAllocation(itemId: item.id, itemName: item.name)).toList(),
    )));
    await _saveInventory();
  }

  Future<void> _addStationItem(CounterStation station) async {
    final nameCtrl = TextEditingController();
    final quantityCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Add item to ${station.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Custom item name')),
        TextField(controller: quantityCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))],
    ));
    final name = nameCtrl.text.trim();
    final quantity = int.tryParse(quantityCtrl.text.trim()) ?? 0;
    nameCtrl.dispose();
    quantityCtrl.dispose();
    if (ok != true || name.isEmpty || quantity < 0) return;
    setState(() => station.allocations.add(StationAllocation(
      itemId: 'custom-${DateTime.now().microsecondsSinceEpoch}', itemName: name, quantity: quantity, isCustom: true,
    )));
    await _saveInventory();
  }

  Future<void> _editAllocation(CounterStation station, StationAllocation allocation) async {
    final ctrl = TextEditingController(text: allocation.quantity.toString());
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${allocation.itemName} · ${station.name}'),
      content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Allocated quantity')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
    ));
    final quantity = int.tryParse(ctrl.text.trim());
    ctrl.dispose();
    if (ok != true || quantity == null || quantity < 0) return;
    setState(() => allocation.quantity = quantity);
    await _saveInventory();
  }

  void _showStationDetails(CounterStation station) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(station.name),
      content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: station.allocations.map((a) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(a.itemName),
        trailing: Text('${a.quantity}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        onTap: () { Navigator.pop(ctx); _editAllocation(station, a); },
      )).toList()))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }

  Future<void> _deleteStation(CounterStation station) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove counter?'), content: Text('Remove ${station.name}?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))],
    ));
    if (ok != true) return;
    setState(() => _inventory.stations.removeWhere((s) => s.id == station.id));
    await _saveInventory();
  }

  Future<void> _assignAllowance(StaffAllowance row) async {
    final amountCtrl = TextEditingController(text: row.amount == 0 ? '' : row.amount.toString());
    final tagCtrl = TextEditingController(text: row.auditTag);
    var source = row.sourceCategory;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: Text('Allowance · ${row.staffName}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Extra allowance (₹)')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: source, decoration: const InputDecoration(labelText: 'Deduct from'), items: const [DropdownMenuItem(value: 'Other Expenses', child: Text('Other Expenses')), DropdownMenuItem(value: 'Setting Bill', child: Text('Setting Bill'))], onChanged: (v) { if (v != null) setDialogState(() => source = v); }),
        TextField(controller: tagCtrl, decoration: const InputDecoration(labelText: 'Audit tag (e.g. Reporting charge)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save allowance'))],
    )));
    final amount = double.tryParse(amountCtrl.text.trim());
    final tag = tagCtrl.text.trim();
    amountCtrl.dispose();
    tagCtrl.dispose();
    if (ok != true || amount == null || amount < 0) return;
    final current = _settlement;
    if (current == null) return;
    final index = current.allowances.indexWhere((a) => a.id == row.id);
    if (index < 0) return;
    setState(() {
      current.allowances[index] = StaffAllowance(id: row.id, staffName: row.staffName, role: row.role, basePay: row.basePay, amount: amount, sourceCategory: source, auditTag: tag);
      current.updatedAt = DateTime.now();
    });
    await StorageService.saveSettlement(current);
  }

  Future<void> _addSettlementStaff() async {
    final nameCtrl = TextEditingController();
    final baseCtrl = TextEditingController(text: '0');
    var role = 'sp';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: const Text('Add settlement row'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Staff name')),
        TextField(controller: baseCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Base pay (₹)')),
        DropdownButtonFormField<String>(value: role, items: const [DropdownMenuItem(value: 'sp', child: Text('SP')), DropdownMenuItem(value: 'cp', child: Text('CP'))], onChanged: (v) { if (v != null) setDialogState(() => role = v); }, decoration: const InputDecoration(labelText: 'Category')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))],
    )));
    final name = nameCtrl.text.trim();
    final base = double.tryParse(baseCtrl.text.trim()) ?? -1;
    nameCtrl.dispose();
    baseCtrl.dispose();
    if (ok != true || name.isEmpty || base < 0 || _settlement == null) return;
    setState(() => _settlement!.allowances.add(StaffAllowance(id: 'manual-${DateTime.now().microsecondsSinceEpoch}', staffName: name, role: role, basePay: base, amount: 0, sourceCategory: 'Other Expenses', auditTag: '')));
    await StorageService.saveSettlement(_settlement!);
  }

  Future<void> _exportSettlement() async {
    final settlement = _settlement;
    if (settlement == null) return;
    await CalculationPdfService.export(settlement);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final query = _staffSearch.trim().toLowerCase();
    final filteredStaff = _masterStaff.where((staff) {
      final category = (staff['category']?.toString() ?? 'BOY').toUpperCase();
      final matchesCategory = _staffFilter == 'ALL' || category == _staffFilter;
      final name = staff['name']?.toString().toLowerCase() ?? '';
      final phone = staff['phone']?.toString().toLowerCase() ?? '';
      final wage = (staff['defaultWage'] as num? ?? 430).toString().toLowerCase();
      return matchesCategory && (query.isEmpty || name.contains(query) || phone.contains(query) || wage.contains(query) || category.toLowerCase().contains(query));
    }).toList()
      ..sort((a, b) => (a['name']?.toString() ?? '').toLowerCase().compareTo((b['name']?.toString() ?? '').toLowerCase()));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Staff Directory', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _initialize, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF17233D), Color(0xFF293B60)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.groups_rounded, color: Colors.white, size: 27)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Your team', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('${_masterStaff.length} staff members', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const Text('Manage names, phone numbers and default wages', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  IconButton(onPressed: _showCloudAuthDialog, tooltip: SupabaseService.isSignedIn ? 'Cloud account' : 'Cloud sign in', icon: Icon(SupabaseService.isSignedIn ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded, color: Colors.white)),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _staffSearchController,
                onChanged: (value) => setState(() => _staffSearch = value),
                decoration: InputDecoration(
                  hintText: 'Search name, phone, wage or category',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _staffSearch.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _staffSearchController.clear(); setState(() => _staffSearch = ''); }),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(children: [
                Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                  for (final filter in ['ALL', 'SP', 'CP', 'BOY'])
                    Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                      label: Text(filter == 'BOY' ? 'Boys' : filter == 'ALL' ? 'All staff' : filter),
                      selected: _staffFilter == filter,
                      onSelected: (_) => setState(() => _staffFilter = filter),
                      showCheckmark: true,
                    )),
                ]))),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: _addMasterStaff, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Add')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
              child: Row(children: [
                Text('${filteredStaff.length} results', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Text('NAME · PHONE · WAGE', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .5)),
              ]),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filteredStaff.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_masterStaff.isEmpty ? Icons.person_add_alt_1_rounded : Icons.search_off_rounded, size: 44, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(_masterStaff.isEmpty ? 'No staff added yet' : 'No matching staff found', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 5),
                    Text(_masterStaff.isEmpty ? 'Add your first team member to get started.' : 'Try another name, phone number, wage or category.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                    if (_masterStaff.isEmpty) ...[const SizedBox(height: 14), FilledButton.icon(onPressed: _addMasterStaff, icon: const Icon(Icons.add), label: const Text('Add staff'))],
                  ])))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                    itemCount: filteredStaff.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final staff = filteredStaff[index];
                      final category = (staff['category']?.toString() ?? 'BOY').toUpperCase();
                      final color = category == 'SP' ? const Color(0xFF315CCB) : category == 'CP' ? const Color(0xFF087F8C) : const Color(0xFF667085);
                      return Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.025), blurRadius: 8, offset: const Offset(0, 2))]),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
                          child: Row(children: [
                            Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12)), child: Text((staff['name']?.toString().trim().isNotEmpty == true ? staff['name'].toString().trim()[0] : '?').toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17))),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(staff['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.call_outlined, size: 13, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Expanded(child: Text(staff['phone']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(6)), child: Text(category == 'BOY' ? 'BOY' : category, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10))),
                                const SizedBox(width: 7),
                                Text(_money((staff['defaultWage'] as num?) ?? 430), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.success)),
                              ]),
                            ])),
                            IconButton(tooltip: 'Edit staff', onPressed: () => _editMasterStaff(staff), icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary)),
                            IconButton(tooltip: 'Delete staff', onPressed: () => _deleteMasterStaff(staff), icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger)),
                          ]),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, {VoidCallback? onTap}) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ]),
          ),
        ),
      );

  void _showBillsDialog(String title, List<CateringBill> bills) {
    final sorted = [...bills]..sort((a, b) => b.date.compareTo(a.date));
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 420, child: sorted.isEmpty
        ? const Text('No archived events found.')
        : ListView.separated(shrinkWrap: true, itemCount: sorted.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (ctx, i) {
          final bill = sorted[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(bill.auditoriumName.isEmpty ? 'Catering event' : bill.auditoriumName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${DateFormat('dd MMM yyyy').format(bill.date)} · ${bill.staffList.length} staff'),
            trailing: Text(_money(bill.getAllTotalBill(bill.taMultiplier)), style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () { Navigator.pop(ctx); widget.onOpenBill?.call(bill); },
          );
        })),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }

  Widget _buildCounts() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            const Expanded(child: Text('Total counts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            FilledButton.icon(onPressed: _addMasterItem, icon: const Icon(Icons.add), label: const Text('Add item')),
          ]),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
            child: Column(children: [
              if (_inventory.masterItems.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('No counts added yet. Tap Add item to create your first item.')),
              ..._inventory.masterItems.asMap().entries.map((entry) {
                final item = entry.value;
                return Column(children: [
                  if (entry.key > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                  ListTile(
                    dense: true,
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Total quantity: ${item.totalQuantity}'),
                    trailing: Wrap(spacing: 0, children: [
                      IconButton(tooltip: 'Edit item', onPressed: () => _editMasterItem(item), icon: const Icon(Icons.edit_outlined, size: 20)),
                      IconButton(tooltip: 'Delete item', onPressed: () => _deleteMasterItem(item), icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20)),
                    ]),
                  ),
                ]);
              }),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('Counter allocation matrix', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(onPressed: _addStation, tooltip: 'Add counter', icon: const Icon(Icons.add_box_outlined)),
          ]),
          LayoutBuilder(builder: (context, constraints) {
            // Specification calls for a two-column counter matrix on mobile and tablet.
            final columns = 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _inventory.stations.map((station) => SizedBox(
                    width: width,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: InkWell(onTap: () => _showStationDetails(station), child: Text(station.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)))),
                            IconButton(tooltip: 'Remove counter', onPressed: () => _deleteStation(station), icon: const Icon(Icons.close, size: 19)),
                          ]),
                          const Divider(),
                          ...station.allocations.take(3).map((allocation) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(children: [
                                  Expanded(child: Text(allocation.itemName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                                  Text('${allocation.quantity}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                  IconButton(constraints: const BoxConstraints.tightFor(width: 30, height: 32), padding: EdgeInsets.zero, tooltip: 'Edit quantity', onPressed: () => _editAllocation(station, allocation), icon: const Icon(Icons.edit_outlined, size: 16)),
                                  if (allocation.isCustom)
                                    IconButton(constraints: const BoxConstraints.tightFor(width: 26, height: 32), padding: EdgeInsets.zero, tooltip: 'Remove item', onPressed: () async { setState(() => station.allocations.remove(allocation)); await _saveInventory(); }, icon: const Icon(Icons.close, size: 16)),
                                ]),
                              )),
                          if (station.allocations.length > 3) TextButton(onPressed: () => _showStationDetails(station), child: Text('View all ${station.allocations.length} counts')),
                          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _addStationItem(station), icon: const Icon(Icons.add, size: 18), label: const Text('Add item'))),
                        ]),
                      ),
                    ),
                  )).toList(),
            );
          }),
        ],
      );

  Widget _buildCalculation() {
    final settlement = _settlement;
    if (settlement == null) {
      return const Center(child: Text('Choose an event date to view SP & CP settlement.'));
    }

    Widget totalTile(String label, String value, IconData icon, {bool emphasize = false}) =>
        Expanded(child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: emphasize ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: emphasize ? AppColors.primary : AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 19, color: emphasize ? Colors.white70 : AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: emphasize ? Colors.white : AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: emphasize ? Colors.white70 : AppColors.textSecondary)),
          ]),
        ));

    Widget allowanceGroup(String role, List<StaffAllowance> rows, Color accent) => _sectionCard(
      '$role allowances (${rows.length})', [
        if (rows.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No staff added yet.', style: TextStyle(color: AppColors.textSecondary))),
        ...rows.map((row) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: 4, height: 42, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.staffName, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('Base ${_money(row.basePay)}  ·  Extra ${_money(row.amount)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              if (row.auditTag.isNotEmpty) Text(row.auditTag, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_money(row.finalTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              TextButton(onPressed: () => _assignAllowance(row), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30)), child: const Text('Edit extra')),
            ]),
          ]),
        )),
      ]);

    final spRows = settlement.allowances.where((row) => row.role.toLowerCase() == 'sp').toList();
    final cpRows = settlement.allowances.where((row) => row.role.toLowerCase() == 'cp').toList();
    final itemized = _selectedBill?.otherExpenseItems ?? const <Map<String, dynamic>>[];

    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
      Row(children: [
        const Expanded(child: Text('SP & CP', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        IconButton.filledTonal(tooltip: 'Export professional PDF', onPressed: _exportSettlement, icon: const Icon(Icons.picture_as_pdf_outlined)),
      ]),
      const SizedBox(height: 8),
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (picked != null) await _loadSettlementForDate(picked);
        },
        child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)), child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.event_outlined)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 3),
            Text(_selectedBill == null ? (settlement.auditoriumName.isEmpty ? 'No archived event for this date' : settlement.auditoriumName) : (_selectedBill!.auditoriumName.isEmpty ? 'Catering event' : _selectedBill!.auditoriumName), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ])),
          const Icon(Icons.edit_calendar_outlined),
        ])),
      ),
      const SizedBox(height: 12),
      Row(children: [totalTile('Base pay', _money(settlement.totalBasePay), Icons.payments_outlined), const SizedBox(width: 9), totalTile('Extra allowances', _money(settlement.totalAllowances), Icons.add_card_outlined)]),
      const SizedBox(height: 9),
      Row(children: [totalTile('Total disbursed', _money(settlement.totalDisbursed), Icons.account_balance_wallet_outlined, emphasize: true), const SizedBox(width: 9), totalTile('Retained expenses', _money(settlement.remainingOther + settlement.remainingSetting), Icons.receipt_long_outlined)]),
      const SizedBox(height: 14),
      TextFormField(
        key: ValueKey('auditor-${settlement.eventDate}'),
        initialValue: settlement.auditorIdentifier,
        decoration: const InputDecoration(labelText: 'Auditor identifier (optional)', prefixIcon: Icon(Icons.badge_outlined), border: OutlineInputBorder(), filled: true),
        onChanged: (value) => settlement.auditorIdentifier = value.trim(),
      ),
      const SizedBox(height: 14),
      Row(children: [const Expanded(child: Text('Staff allowances', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))), TextButton.icon(onPressed: _addSettlementStaff, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add staff'))]),
      allowanceGroup('SP', spRows, const Color(0xFF2563EB)),
      const SizedBox(height: 10),
      allowanceGroup('CP', cpRows, const Color(0xFFD97706)),
      const SizedBox(height: 12),
      _sectionCard('Expense balance', [
        _summaryLine('Other expenses · original', _money(settlement.originalOtherExpenses)),
        _summaryLine('Other expenses · deductions', _money(settlement.otherDeductions)),
        _summaryLine('Other expenses · remaining', _money(settlement.remainingOther), bold: true),
        const Divider(height: 18),
        _summaryLine('Setting bill · original', _money(settlement.originalSettingBill)),
        _summaryLine('Setting bill · deductions', _money(settlement.settingDeductions)),
        _summaryLine('Setting bill · remaining', _money(settlement.remainingSetting), bold: true),
      ]),
      if (itemized.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionCard('Other expense details', [
          ...itemized.map((item) => _summaryLine(item['name']?.toString() ?? 'Expense', _money((item['amount'] as num?)?.toDouble() ?? 0))),
          const Divider(height: 18),
          _summaryLine('Total itemized expenses', _money(itemized.fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0))), bold: true),
        ]),
      ],
      const SizedBox(height: 16),
      SizedBox(height: 50, child: FilledButton.icon(onPressed: () async {
        await StorageService.saveSettlement(settlement);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SP & CP settlement saved')));
      }, icon: const Icon(Icons.save_outlined), label: const Text('Save SP & CP settlement'))),
      const SizedBox(height: 9),
      SizedBox(height: 48, child: OutlinedButton.icon(onPressed: _exportSettlement, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Export settlement PDF'))),
    ]);
  }

  Widget _sectionCard(String title, List<Widget> children) => Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 8), ...children])));

  Widget _summaryLine(String label, String value, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontWeight: bold ? FontWeight.w700 : FontWeight.w400))), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600))]));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
