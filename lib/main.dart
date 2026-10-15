import 'dart:async';
import 'package:flutter/material.dart';
import 'constants/app_colors.dart';
import 'models/staff_item.dart';
import 'models/catering_bill.dart';
import 'services/storage_service.dart';
import 'screens/reporting_screen.dart';
import 'screens/outing_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/other_screen.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Supabase is optional until the build is supplied with credentials.
  try { await SupabaseService.initialize(); } catch (_) { /* app remains usable offline */ }
  // If an authenticated session was restored, retry any locally queued cloud writes.
  unawaited(StorageService.flushPendingCloudSync());
  runApp(const StaffBillingApp());
}

class StaffBillingApp extends StatelessWidget {
  const StaffBillingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaterPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          surface: AppColors.card,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({Key? key}) : super(key: key);

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  Timer? _debounceSaveTimer;

  String currentBillId = DateTime.now().millisecondsSinceEpoch.toString();
  String auditoriumName = '';
  DateTime eventDate = DateTime.now();
  double otherExpenses = 0.0;
  double settingExpenses = 0.0;
  List<Map<String, dynamic>> otherExpenseItems = [];
  double taMultiplier = 3.0;
  int groupSize = 10;
  final Map<int, String> groupGpay = {};

  final List<StaffItem> sharedBoysList = [];
  final List<StaffItem> sharedSpList = [];
  final List<StaffItem> sharedCpList = [];

  @override
  void initState() {
    super.initState();
    _restoreActiveBillFromStorage();
    StorageService.dataRevision.addListener(_onRestoredDataChanged);
  }

  void _onRestoredDataChanged() {
    _debounceSaveTimer?.cancel();
    _restoreActiveBillFromStorage();
  }

  Future<void> _restoreActiveBillFromStorage() async {
    final active = await StorageService.getActiveBill();
    if (!mounted) return;
    if (active != null) {
      setState(() {
        currentBillId = active.id;
        auditoriumName = active.auditoriumName;
        eventDate = active.date;
        otherExpenses = active.otherExpenses;
        settingExpenses = active.settingExpenses;
        otherExpenseItems = active.otherExpenseItems.map((e) => Map<String, dynamic>.from(e)).toList();
        taMultiplier = active.taMultiplier;
        groupSize = active.groupSize;
        groupGpay.clear();
        groupGpay.addAll(active.groupGpay);

        sharedBoysList.clear();
        sharedBoysList.addAll(active.boys);
        sharedSpList.clear();
        sharedSpList.addAll(active.spList);
        sharedCpList.clear();
        sharedCpList.addAll(active.cpList);
      });
    } else if (mounted) {
      setState(() {
        currentBillId = DateTime.now().millisecondsSinceEpoch.toString();
        auditoriumName = '';
        eventDate = DateTime.now();
        otherExpenses = 0;
        settingExpenses = 0;
        otherExpenseItems = [];
        taMultiplier = 3.0;
        groupSize = 10;
        groupGpay.clear();
        sharedBoysList.clear();
        sharedSpList.clear();
        sharedCpList.clear();
      });
    }
  }

  void _triggerAutoSave() {
    _debounceSaveTimer?.cancel();
    _debounceSaveTimer = Timer(const Duration(milliseconds: 300), () async {
      final bill = CateringBill(
        id: currentBillId,
        auditoriumName: auditoriumName.trim(),
        date: eventDate,
        otherExpenses: otherExpenses,
        settingExpenses: settingExpenses,
        otherExpenseItems: otherExpenseItems,
        taMultiplier: taMultiplier,
        groupSize: groupSize,
        staffList: [...sharedBoysList, ...sharedSpList, ...sharedCpList],
        groupGpay: groupGpay,
      );
      await StorageService.saveBill(bill);
    });
  }

  void _onListParsed(List<StaffItem> boys, List<StaffItem> sp, List<StaffItem> cp) {
    setState(() {
      sharedBoysList.clear();
      sharedBoysList.addAll(boys);
      sharedSpList.clear();
      sharedSpList.addAll(sp);
      sharedCpList.clear();
      sharedCpList.addAll(cp);
      currentBillId = DateTime.now().millisecondsSinceEpoch.toString();
    });
    _triggerAutoSave();
  }

  void _startNewWork() async {
    await StorageService.clearActiveBillTracking();
    setState(() {
      currentBillId = DateTime.now().millisecondsSinceEpoch.toString();
      auditoriumName = '';
      eventDate = DateTime.now();
      otherExpenses = 0.0;
      settingExpenses = 0.0;
      otherExpenseItems = [];
      taMultiplier = 3.0;
      groupSize = 10;
      groupGpay.clear();
      sharedBoysList.clear();
      sharedSpList.clear();
      sharedCpList.clear();
      _currentIndex = 0;
    });
  }

  void _loadExistingBillFromCalendar(CateringBill bill) {
    setState(() {
      currentBillId = bill.id;
      auditoriumName = bill.auditoriumName;
      eventDate = bill.date;
      otherExpenses = bill.otherExpenses;
      settingExpenses = bill.settingExpenses;
      otherExpenseItems = bill.otherExpenseItems.map((e) => Map<String, dynamic>.from(e)).toList();
      taMultiplier = bill.taMultiplier;
      groupSize = bill.groupSize;
      groupGpay.clear();
      groupGpay.addAll(bill.groupGpay);

      sharedBoysList.clear();
      sharedBoysList.addAll(bill.boys);
      sharedSpList.clear();
      sharedSpList.addAll(bill.spList);
      sharedCpList.clear();
      sharedCpList.addAll(bill.cpList);

      _currentIndex = 1;
    });
    _triggerAutoSave();
  }

  @override
  void dispose() {
    StorageService.dataRevision.removeListener(_onRestoredDataChanged);
    _debounceSaveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      ReportingScreen(
        boysList: sharedBoysList,
        spList: sharedSpList,
        cpList: sharedCpList,
        onListParsed: _onListParsed,
        onDataChanged: _triggerAutoSave,
        onStartNewWork: _startNewWork,
        onSubmitToOuting: () {
          _triggerAutoSave();
          setState(() => _currentIndex = 1);
        },
      ),
      OutingScreen(
        billId: currentBillId,
        auditoriumName: auditoriumName,
        eventDate: eventDate,
        otherExpenses: otherExpenses,
        settingExpenses: settingExpenses,
        otherExpenseItems: otherExpenseItems,
        multiplier: taMultiplier,
        groupSize: groupSize,
        groupGpay: groupGpay,
        boysList: sharedBoysList,
        spList: sharedSpList,
        cpList: sharedCpList,
        onUpdateAuditorium: (val) {
          auditoriumName = val;
          _triggerAutoSave();
        },
        onUpdateDate: (val) {
          setState(() => eventDate = val);
          _triggerAutoSave();
        },
        onUpdateOtherExp: (val) {
          otherExpenses = val;
          _triggerAutoSave();
        },
        onUpdateSettingExp: (val) {
          settingExpenses = val;
          _triggerAutoSave();
        },
        onUpdateOtherExpenseItems: (items) {
          setState(() {
            otherExpenseItems = items.map((e) => Map<String, dynamic>.from(e)).toList();
            otherExpenses = otherExpenseItems.fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));
          });
          _triggerAutoSave();
        },
        onUpdateMultiplier: (val) {
          setState(() => taMultiplier = val);
          _triggerAutoSave();
        },
        onUpdateGroupSize: (val) {
          setState(() => groupSize = val);
          _triggerAutoSave();
        },
        onDataChanged: _triggerAutoSave,
      ),
      CalendarScreen(
        onSelectBill: _loadExistingBillFromCalendar,
      ),
      OtherScreen(onOpenBill: _loadExistingBillFromCalendar),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: AppColors.primarySurface,
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Colors.white, size: 22);
              }
              return const IconThemeData(color: AppColors.textSecondary, size: 22);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                );
              }
              return const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 11.5,
              );
            }),
          ),
          child: NavigationBar(
            height: 64,
            backgroundColor: Colors.white,
            elevation: 0,
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              _triggerAutoSave();
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.edit_note_rounded),
                selectedIcon: Icon(Icons.edit_note_rounded),
                label: 'Reporting',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_rounded),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Outing',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_rounded),
                selectedIcon: Icon(Icons.calendar_month_rounded),
                label: 'Calendar',
              ),
              NavigationDestination(
                icon: Icon(Icons.dashboard_customize_rounded),
                selectedIcon: Icon(Icons.dashboard_customize_rounded),
                label: 'Staff',
              ),
            ],
          ),
        ),
      ),
    );
  }
}