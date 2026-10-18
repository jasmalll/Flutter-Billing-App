import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import '../models/staff_item.dart';
import '../services/pdf_service.dart';
import '../widgets/outing_row_item.dart';

class OutingScreen extends StatefulWidget {
  final String billId;
  final String auditoriumName;
  final DateTime eventDate;
  final double otherExpenses;
  final double settingExpenses; // Settings column
  final List<Map<String, dynamic>> otherExpenseItems;
  final double multiplier;
  final int groupSize; // 10, 11, 12, 13, 14, 15
  final Map<int, String> groupGpay;
  final List<StaffItem> boysList;
  final List<StaffItem> spList;
  final List<StaffItem> cpList;
  final ValueChanged<String> onUpdateAuditorium;
  final ValueChanged<DateTime> onUpdateDate;
  final ValueChanged<double> onUpdateOtherExp;
  final ValueChanged<double> onUpdateSettingExp;
  final ValueChanged<List<Map<String, dynamic>>> onUpdateOtherExpenseItems;
  final ValueChanged<double> onUpdateMultiplier;
  final ValueChanged<int> onUpdateGroupSize;
  final VoidCallback onDataChanged;

  const OutingScreen({
    Key? key,
    required this.billId,
    required this.auditoriumName,
    required this.eventDate,
    required this.otherExpenses,
    required this.settingExpenses,
    required this.otherExpenseItems,
    required this.multiplier,
    required this.groupSize,
    required this.groupGpay,
    required this.boysList,
    required this.spList,
    required this.cpList,
    required this.onUpdateAuditorium,
    required this.onUpdateDate,
    required this.onUpdateOtherExp,
    required this.onUpdateSettingExp,
    required this.onUpdateOtherExpenseItems,
    required this.onUpdateMultiplier,
    required this.onUpdateGroupSize,
    required this.onDataChanged,
  }) : super(key: key);

  @override
  State<OutingScreen> createState() => _OutingScreenState();
}

class _OutingScreenState extends State<OutingScreen> {
  late TextEditingController _auditoriumCtrl;
  late TextEditingController _otherExpCtrl;
  late TextEditingController _settingExpCtrl;
  late TextEditingController _multiplierCtrl;
  final Map<int, TextEditingController> _gpayControllers = {};

  @override
  void initState() {
    super.initState();
    _auditoriumCtrl = TextEditingController(text: widget.auditoriumName);
    _otherExpCtrl = TextEditingController(text: widget.otherExpenses > 0 ? widget.otherExpenses.toInt().toString() : '');
    _settingExpCtrl = TextEditingController(text: widget.settingExpenses > 0 ? widget.settingExpenses.toInt().toString() : '');
    _multiplierCtrl = TextEditingController(
      text: (widget.multiplier % 1 == 0) ? widget.multiplier.toInt().toString() : widget.multiplier.toString(),
    );

    widget.groupGpay.forEach((k, v) {
      _gpayControllers[k] = TextEditingController(text: v);
    });
  }

  @override
  void didUpdateWidget(covariant OutingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.auditoriumName != _auditoriumCtrl.text) {
      _auditoriumCtrl.text = widget.auditoriumName;
    }
    if (widget.otherExpenses != oldWidget.otherExpenses) {
      _otherExpCtrl.text = widget.otherExpenses > 0 ? widget.otherExpenses.toInt().toString() : '';
    }
    if (widget.settingExpenses != oldWidget.settingExpenses) {
      _settingExpCtrl.text = widget.settingExpenses > 0 ? widget.settingExpenses.toInt().toString() : '';
    }
    if (widget.multiplier != oldWidget.multiplier) {
      _multiplierCtrl.text = (widget.multiplier % 1 == 0) ? widget.multiplier.toInt().toString() : widget.multiplier.toString();
    }
    widget.groupGpay.forEach((k, v) {
      _gpayControllers.putIfAbsent(k, () => TextEditingController(text: v));
    });
  }

  @override
  void dispose() {
    _auditoriumCtrl.dispose();
    _otherExpCtrl.dispose();
    _settingExpCtrl.dispose();
    _multiplierCtrl.dispose();
    for (var c in _gpayControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get allStaffTa {
    double t = 0;
    for (var b in widget.boysList) {
      t += b.getCalculatedTa(widget.multiplier);
    }
    for (var s in widget.spList) {
      t += s.getCalculatedTa(widget.multiplier);
    }
    for (var c in widget.cpList) {
      t += c.getCalculatedTa(widget.multiplier);
    }
    return t;
  }

  double get allStaffBill {
    double t = 0;
    for (var b in widget.boysList) {
      t += b.getTotal(widget.multiplier);
    }
    for (var s in widget.spList) {
      t += s.getTotal(widget.multiplier);
    }
    for (var c in widget.cpList) {
      t += c.getTotal(widget.multiplier);
    }
    return t;
  }

  // TA-il settings koodilla
  double get grandTotalTa => allStaffTa;
  // Final bill-il settings expenses koodum
  double get grandTotalBill => allStaffBill + widget.otherExpenses + widget.settingExpenses;

  Future<void> _editOtherExpense({Map<String, dynamic>? existing, int? index}) async {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final amountCtrl = TextEditingController(text: existing?['amount']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add other expense' : 'Edit other expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Expense name', hintText: 'Reporting charge')),
            TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (₹)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim());
    nameCtrl.dispose();
    amountCtrl.dispose();
    if (ok != true || name.isEmpty || amount == null || amount < 0) return;
    final items = widget.otherExpenseItems.map((e) => Map<String, dynamic>.from(e)).toList();
    if (items.isEmpty && widget.otherExpenses > 0 && existing == null) {
      items.add({'name': 'Existing other expenses', 'amount': widget.otherExpenses});
    }
    final value = <String, dynamic>{'name': name, 'amount': amount};
    if (index != null && index >= 0 && index < items.length) {
      items[index] = value;
    } else {
      items.add(value);
    }
    widget.onUpdateOtherExpenseItems(items);
    if (mounted) setState(() {});
  }

  void _deleteOtherExpense(int index) {
    final items = widget.otherExpenseItems.map((e) => Map<String, dynamic>.from(e)).toList();
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    widget.onUpdateOtherExpenseItems(items);
    setState(() {});
  }

  void _editWageDialog(StaffItem item) {
    final wageCtrl = TextEditingController(text: item.wage.toInt().toString());
    final taCtrl = TextEditingController(text: item.getCalculatedTa(widget.multiplier).toInt().toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Wage for #${item.index} ${item.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Select:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [440, 450, 460].map((quickWage) {
                final bool isSelected = item.wage.toInt() == quickWage;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          item.wage = quickWage.toDouble();
                        });
                        widget.onDataChanged();
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : const Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          '₹$quickWage',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: isSelected ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Manual TA (final Outing amount):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: taCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter final TA amount', prefixText: '₹ ', filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Or Custom Wage:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: wageCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter wage',
                prefixText: '₹ ',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final w = double.tryParse(wageCtrl.text.trim());
              final ta = double.tryParse(taCtrl.text.trim());
              if (w != null && w >= 0 && ta != null && ta >= 0) {
                setState(() {
                  item.wage = w;
                  item.baseTa = widget.multiplier > 0 ? (ta / widget.multiplier) : ta;
                });
                widget.onDataChanged();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _generateWhatsAppBillingText() {
    StringBuffer sb = StringBuffer();
    final dateStr = DateFormat('dd/MM/yyyy').format(widget.eventDate);

    if (_auditoriumCtrl.text.trim().isNotEmpty) {
      sb.writeln('*${_auditoriumCtrl.text.trim().toUpperCase()}*');
      sb.writeln('Date: $dateStr\n');
    }

    // Dynamic Group Batching
    for (int i = 0; i < widget.boysList.length; i += widget.groupSize) {
      int end = (i + widget.groupSize < widget.boysList.length) ? i + widget.groupSize : widget.boysList.length;
      List<StaffItem> batch = widget.boysList.sublist(i, end);
      int gIdx = (i ~/ widget.groupSize) + 1;

      for (var b in batch) {
        if (!b.isPresent) {
          sb.writeln('${b.index}.🔴');
        } else {
          String pStr = b.phone.isNotEmpty ? ' ${b.phone}' : '';
          double calcTa = b.getCalculatedTa(widget.multiplier);
          double total = b.getTotal(widget.multiplier);
          String check = b.outingStatus.isNotEmpty ? ' ${b.outingStatus}' : '';

          String wageDisplay = b.minusAmount > 0
              ? '(${b.wage.toInt()} - ${b.minusAmount.toInt()})'
              : '${b.wage.toInt()}';

          sb.writeln('${b.index}.${b.name}$pStr  $wageDisplay + ${calcTa.toInt()} = ${total.toInt()}$check');
        }
      }

      double bTa = batch.fold(0.0, (sum, b) => sum + b.getCalculatedTa(widget.multiplier));
      double bBill = batch.fold(0.0, (sum, b) => sum + b.getTotal(widget.multiplier));
      String gpay = _gpayControllers[gIdx]?.text.trim() ?? '';

      sb.writeln('\nTotal ta:- ${bTa.toInt()}');
      sb.writeln('Total bill:- ${bBill.toInt()}');
      if (gpay.isNotEmpty) {
        sb.writeln('Gpay :- $gpay');
      }
      sb.writeln('');
    }

    if (widget.spList.isNotEmpty) {
      sb.writeln('Sp');
      for (var s in widget.spList) {
        if (!s.isPresent) {
          sb.writeln('👉🏻 ${s.name} 🔴');
        } else {
          double calcTa = s.getCalculatedTa(widget.multiplier);
          double total = s.getTotal(widget.multiplier);
          String check = s.outingStatus.isNotEmpty ? ' ${s.outingStatus}' : '';
          sb.writeln('👉🏻 ${s.name}  ${s.wage.toInt()} + ${calcTa.toInt()} = ${total.toInt()}$check');
        }
      }
      double spTa = widget.spList.fold(0.0, (sum, s) => sum + s.getCalculatedTa(widget.multiplier));
      double spBill = widget.spList.fold(0.0, (sum, s) => sum + s.getTotal(widget.multiplier));
      sb.writeln('\nTotal ta:- ${spTa.toInt()}');
      sb.writeln('Total bill:- ${spBill.toInt()}\n');
    }

    if (widget.cpList.isNotEmpty) {
      sb.writeln('Cp');
      for (var c in widget.cpList) {
        if (!c.isPresent) {
          sb.writeln('👉🏻 ${c.name} 🔴');
        } else {
          double calcTa = c.getCalculatedTa(widget.multiplier);
          double total = c.getTotal(widget.multiplier);
          String check = c.outingStatus.isNotEmpty ? ' ${c.outingStatus}' : '';
          sb.writeln('👉🏻 ${c.name}  ${c.wage.toInt()} + ${calcTa.toInt()} = ${total.toInt()}$check');
        }
      }
      double cpTa = widget.cpList.fold(0.0, (sum, c) => sum + c.getCalculatedTa(widget.multiplier));
      double cpBill = widget.cpList.fold(0.0, (sum, c) => sum + c.getTotal(widget.multiplier));
      sb.writeln('\nTotal ta:- ${cpTa.toInt()}');
      sb.writeln('Total bill:- ${cpBill.toInt()}\n');
    }

    sb.writeln('\n\n');
    sb.writeln('Other expenses:- ${widget.otherExpenses.toInt()}');
    if (widget.settingExpenses > 0) {
      sb.writeln('Settings expenses:- ${widget.settingExpenses.toInt()}');
    }
    sb.writeln('All total ta:- ${grandTotalTa.toInt()}');
    sb.writeln('All total bill:- ${grandTotalBill.toInt()}');

    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    bool hasData = widget.boysList.isNotEmpty || widget.spList.isNotEmpty || widget.cpList.isNotEmpty;

    if (!hasData) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Outing Billing', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                const Text('No Active Roster Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                const Text('Please add your staff list in the Reporting tab to perform billing.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    // Dynamic Batching
    List<List<StaffItem>> batches = [];
    for (int i = 0; i < widget.boysList.length; i += widget.groupSize) {
      int end = (i + widget.groupSize < widget.boysList.length) ? i + widget.groupSize : widget.boysList.length;
      batches.add(widget.boysList.sublist(i, end));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Outing Billing', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
            Text('Final Staff & Event Ledger', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
          ],
        ),
        actions: [
          // Dynamic Group Size Dropdown
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: widget.groupSize,
                dropdownColor: AppColors.primarySurface,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
                items: [10, 11, 12, 13, 14, 15].map((int val) {
                  return DropdownMenuItem<int>(
                    value: val,
                    child: Text(
                      'Grp: $val',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
                onChanged: (int? newVal) {
                  if (newVal != null) {
                    widget.onUpdateGroupSize(newVal);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 4),

          // TA Multiplier Badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('TA:×', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 2),
                SizedBox(
                  width: 32,
                  height: 28,
                  child: TextField(
                    controller: _multiplierCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w800, fontSize: 12),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                    onChanged: (val) {
                      final m = double.tryParse(val.trim());
                      if (m != null && m > 0) {
                        widget.onUpdateMultiplier(m);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
            tooltip: 'Export PDF',
            onPressed: () {
              Map<int, String> gpayMap = {};
              _gpayControllers.forEach((k, v) => gpayMap[k] = v.text.trim());
              PdfService.exportOutingPdf(
                auditoriumName: _auditoriumCtrl.text.trim(),
                eventDate: widget.eventDate,
                boysList: widget.boysList,
                spList: widget.spList,
                cpList: widget.cpList,
                otherExpenses: widget.otherExpenses,
                settingExpenses: widget.settingExpenses,
                otherExpenseItems: widget.otherExpenseItems,
                multiplier: widget.multiplier,
                groupSize: widget.groupSize,
                groupGpay: gpayMap,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Event Details Meta Card
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.015), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  // Venue Field
                  TextField(
                    controller: _auditoriumCtrl,
                    onChanged: widget.onUpdateAuditorium,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter Auditorium / Venue Name',
                      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.normal),
                      isDense: true,
                      prefixIcon: const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Date, Other Expenses, Setting Expenses Row
                  Row(
                    children: [
                      // Date Selector
                      Expanded(
                        flex: 4,
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: widget.eventDate,
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) widget.onUpdateDate(picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textSecondary),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    DateFormat('dd MMM yy').format(widget.eventDate),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Other Expenses
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _otherExpCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          onChanged: (val) {
                            widget.onUpdateOtherExp(double.tryParse(val.trim()) ?? 0.0);
                          },
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: '0',
                            prefixText: 'Other:₹',
                            prefixStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Setting Expenses Column
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _settingExpCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          onChanged: (val) {
                            widget.onUpdateSettingExp(double.tryParse(val.trim()) ?? 0.0);
                          },
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: '0',
                            prefixText: 'Setting:₹',
                            prefixStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Collapsible Other Expense Breakdown
            Container(
              margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  title: Row(
                    children: [
                      const Text(
                        'Other expense breakdown',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                      if (widget.otherExpenseItems.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${widget.otherExpenseItems.length}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _editOtherExpense(),
                        icon: const Icon(Icons.add, size: 15),
                        label: const Text('Add', style: TextStyle(fontSize: 11)),
                      ),
                      const Icon(Icons.expand_more, size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                  children: [
                    const Divider(height: 1, color: AppColors.borderSubtle),
                    const SizedBox(height: 4),
                    if (widget.otherExpenseItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Add named items such as Reporting charge ₹50.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ),
                      )
                    else
                      ...widget.otherExpenseItems.asMap().entries.map((entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(child: Text(entry.value['name']?.toString() ?? 'Expense', style: const TextStyle(fontSize: 12))),
                                Text('₹${((entry.value['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                  onPressed: () => _editOtherExpense(existing: entry.value, index: entry.key),
                                  icon: const Icon(Icons.edit_outlined, size: 15),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                  onPressed: () => _deleteOtherExpense(entry.key),
                                  icon: const Icon(Icons.delete_outline, size: 15, color: AppColors.danger),
                                ),
                              ],
                            ),
                          )),
                  ],
                ),
              ),
            ),

            // Billing Ledger Groups (Dynamic Grouping)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  ...batches.asMap().entries.map((entry) {
                    int gIdx = entry.key + 1;
                    List<StaffItem> batch = entry.value;

                    _gpayControllers.putIfAbsent(gIdx, () => TextEditingController(text: widget.groupGpay[gIdx] ?? ''));

                    double bTa = batch.fold(0.0, (sum, b) => sum + b.getCalculatedTa(widget.multiplier));
                    double bBill = batch.fold(0.0, (sum, b) => sum + b.getTotal(widget.multiplier));
                    int batchPresent = batch.where((b) => b.isPresent).length;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'GROUP $gIdx (Boys ${batch.first.index} - ${batch.last.index})',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySurface,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$batchPresent / ${batch.length} Present',
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w700, fontSize: 10.5),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          ...batch.map((b) => OutingRowItem(
                                key: ValueKey(b.index),
                                item: b,
                                multiplier: widget.multiplier,
                                onDataChanged: widget.onDataChanged,
                                onEditWage: () => _editWageDialog(b),
                              )),

                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
                              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total TA: ₹${bTa.toInt()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.success)),
                                    Text('Group Total: ₹${bBill.toInt()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _gpayControllers[gIdx],
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                  onChanged: (val) {
                                    widget.groupGpay[gIdx] = val.trim();
                                    widget.onDataChanged();
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'GPay :- Name & Number / UPI',
                                    hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.primary),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),

                  if (widget.spList.isNotEmpty) ...[
                    _buildSpecialRoleSection('SUPERVISORS (SP)', widget.spList, AppColors.roleSp),
                    const SizedBox(height: 14),
                  ],

                  if (widget.cpList.isNotEmpty) ...[
                    _buildSpecialRoleSection('CAPTAINS (CP)', widget.cpList, AppColors.roleCp),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),

            // Grand Total Sticky Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: AppColors.border)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, -3)),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ALL TA: ₹${grandTotalTa.toInt()}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.success)),
                      Text('ALL TOTAL: ₹${grandTotalBill.toInt()}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                    label: const Text('WhatsApp Format', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    onPressed: () {
                      final text = _generateWhatsAppBillingText();
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✔ Report copied! Paste directly into WhatsApp.'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialRoleSection(String title, List<StaffItem> list, Color color) {
    double totalTa = list.fold(0.0, (sum, s) => sum + s.getCalculatedTa(widget.multiplier));
    double totalBill = list.fold(0.0, (sum, s) => sum + s.getTotal(widget.multiplier));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(11))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                Text('${list.length} Members', style: const TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
          ...list.map((s) => OutingRowItem(
                key: ValueKey(s.index),
                item: s,
                multiplier: widget.multiplier,
                onDataChanged: widget.onDataChanged,
                onEditWage: () => _editWageDialog(s),
              )),
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total TA: ₹${totalTa.toInt()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.success)),
                Text('Total Bill: ₹${totalBill.toInt()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
