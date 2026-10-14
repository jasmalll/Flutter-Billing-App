import 'dart:convert';
import 'staff_item.dart';

class CateringBill {
  final String id;
  String auditoriumName;
  DateTime date;
  DateTime updatedAt;
  double otherExpenses;
  double settingExpenses; // Settings column
  List<Map<String, dynamic>> otherExpenseItems;
  double taMultiplier;
  int groupSize; // 10, 11, 12, 13, 14, 15 (Default: 10)
  List<StaffItem> staffList;
  Map<int, String> groupGpay;

  CateringBill({
    required this.id,
    required this.auditoriumName,
    required this.date,
    DateTime? updatedAt,
    this.otherExpenses = 0.0,
    this.settingExpenses = 0.0,
    List<Map<String, dynamic>>? otherExpenseItems,
    this.taMultiplier = 3.0,
    this.groupSize = 10,
    required this.staffList,
    required this.groupGpay,
  }) : updatedAt = updatedAt ?? DateTime.now(),
       otherExpenseItems = otherExpenseItems ?? [];

  List<StaffItem> get boys => staffList.where((s) => s.role == 'boy').toList();
  List<StaffItem> get spList => staffList.where((s) => s.role == 'sp').toList();
  List<StaffItem> get cpList => staffList.where((s) => s.role == 'cp').toList();

  // TA-il otherExpenses mathram koodum, settings koodilla
  double getAllTotalTa(double mult) {
    double staffTa = staffList.fold(0.0, (sum, s) => sum + s.getCalculatedTa(mult));
    return staffTa + otherExpenses;
  }

  // Bill-il staff bill + otherExpenses + settingExpenses koodum
  double getAllTotalBill(double mult) {
    double staffBill = staffList.fold(0.0, (sum, s) => sum + s.getTotal(mult));
    return staffBill + otherExpenses + settingExpenses;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'auditoriumName': auditoriumName,
        'date': date.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'otherExpenses': otherExpenses,
        'settingExpenses': settingExpenses,
        'otherExpenseItems': otherExpenseItems,
        'taMultiplier': taMultiplier,
        'groupSize': groupSize,
        'staffList': staffList.map((s) => s.toMap()).toList(),
        'groupGpay': groupGpay.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory CateringBill.fromMap(Map<String, dynamic> map) {
    Map<int, String> gpay = {};
    if (map['groupGpay'] != null) {
      (map['groupGpay'] as Map<String, dynamic>).forEach((k, v) {
        gpay[int.parse(k)] = v.toString();
      });
    }
    return CateringBill(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      auditoriumName: map['auditoriumName'] ?? '',
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      otherExpenses: (map['otherExpenses'] as num?)?.toDouble() ?? 0.0,
      settingExpenses: (map['settingExpenses'] as num?)?.toDouble() ?? 0.0,
      otherExpenseItems: (map['otherExpenseItems'] as List<dynamic>? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      taMultiplier: (map['taMultiplier'] as num?)?.toDouble() ?? 3.0,
      groupSize: (map['groupSize'] as num?)?.toInt() ?? 10,
      staffList: (map['staffList'] as List<dynamic>? ?? []).map((e) => StaffItem.fromMap(e)).toList(),
      groupGpay: gpay,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory CateringBill.fromJson(String source) => CateringBill.fromMap(jsonDecode(source));
}