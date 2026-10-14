class StaffItem {
  final int index;
  String name;
  String phone;
  final String role; // 'boy', 'sp', 'cp'
  String attendance; // '' (blank) -> '✅' -> '🔴'
  double baseTa;
  double minusAmount;
  double wage; // Default 430, editable per staff
  double? suggestedWage; // Master directory suggestion; applied only after supervisor taps
  String outingStatus; // '' -> '✅' -> '❎'

  StaffItem({
    required this.index,
    required this.name,
    required this.phone,
    required this.role,
    this.attendance = '',
    this.baseTa = 0.0,
    this.minusAmount = 0.0,
    this.wage = 430.0,
    this.suggestedWage,
    this.outingStatus = '',
  });

  bool get isPresent => attendance == '✅';

  double getCalculatedTa(double multiplier) => isPresent ? (baseTa * multiplier) : 0.0;

  double getEffectiveWage() {
    if (!isPresent) return 0.0;
    double eff = wage - minusAmount;
    return eff > 0 ? eff : 0.0;
  }

  double getTotal(double multiplier) {
    if (!isPresent) return 0.0;
    return getEffectiveWage() + getCalculatedTa(multiplier);
  }

  Map<String, dynamic> toMap() => {
        'index': index,
        'name': name,
        'phone': phone,
        'role': role,
        'attendance': attendance,
        'baseTa': baseTa,
        'minusAmount': minusAmount,
        'wage': wage,
        'suggestedWage': suggestedWage,
        'outingStatus': outingStatus,
      };

  factory StaffItem.fromMap(Map<String, dynamic> map) => StaffItem(
        index: map['index'] ?? 0,
        name: map['name'] ?? '',
        phone: map['phone'] ?? '',
        role: map['role'] ?? 'boy',
        attendance: map['attendance'] ?? '',
        baseTa: (map['baseTa'] as num?)?.toDouble() ?? 0.0,
        minusAmount: (map['minusAmount'] as num?)?.toDouble() ?? 0.0,
        wage: (map['wage'] as num?)?.toDouble() ?? 430.0,
        suggestedWage: (map['suggestedWage'] as num?)?.toDouble(),
        outingStatus: map['outingStatus'] ?? '',
      );
}