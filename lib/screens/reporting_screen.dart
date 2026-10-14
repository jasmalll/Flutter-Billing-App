import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/staff_item.dart';
import '../widgets/staff_row_item.dart';
import '../services/storage_service.dart';

class ReportingScreen extends StatefulWidget {
  final List<StaffItem> boysList;
  final List<StaffItem> spList;
  final List<StaffItem> cpList;
  final Function(List<StaffItem>, List<StaffItem>, List<StaffItem>) onListParsed;
  final VoidCallback onDataChanged;
  final VoidCallback onStartNewWork;
  final VoidCallback onSubmitToOuting;

  const ReportingScreen({
    Key? key,
    required this.boysList,
    required this.spList,
    required this.cpList,
    required this.onListParsed,
    required this.onDataChanged,
    required this.onStartNewWork,
    required this.onSubmitToOuting,
  }) : super(key: key);

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen> {
  Future<void> _parseListInput(String text) async {
    List<StaffItem> bList = [];
    List<StaffItem> sList = [];
    List<StaffItem> cList = [];

    final lines = text.split('\n');
    String currentRole = 'boy';

    int bIdx = 1;
    int sIdx = 1;
    int cIdx = 1;

    for (var rawLine in lines) {
      String line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.toLowerCase() == 'sp' || line.toLowerCase().startsWith('sp ')) {
        currentRole = 'sp';
        continue;
      }
      if (line.toLowerCase() == 'cp' || line.toLowerCase().startsWith('cp ')) {
        currentRole = 'cp';
        continue;
      }

      line = line.replaceAll('👉🏻', '').replaceAll('👉', '').trim();

      if (currentRole == 'boy') {
        String clean = line;
        if (RegExp(r'^\d+[\.\)]').hasMatch(clean)) {
          clean = clean.replaceFirst(RegExp(r'^\d+[\.\)]'), '').trim();
        }

        String name = clean;
        String phone = '';

        final phoneMatch = RegExp(r'(\+?\d[\d\s-]{7,}\d)').firstMatch(clean);
        if (phoneMatch != null) {
          phone = phoneMatch.group(0)!.trim();
          name = clean.replaceFirst(phone, '').replaceAll(';', '').trim();
        } else {
          name = clean.replaceAll(';', '').trim();
        }

        bList.add(StaffItem(
          index: bIdx++,
          name: name.isEmpty ? 'Staff $bIdx' : name,
          phone: phone,
          role: 'boy',
          attendance: '',
        ));
      } else if (currentRole == 'sp') {
        sList.add(StaffItem(
          index: sIdx++,
          name: line.replaceAll(';', '').trim(),
          phone: '',
          role: 'sp',
          attendance: '',
        ));
      } else if (currentRole == 'cp') {
        cList.add(StaffItem(
          index: cIdx++,
          name: line.replaceAll(';', '').trim(),
          phone: '',
          role: 'cp',
          attendance: '',
        ));
      }
    }

    // Directory wage matching: Boys require both name and phone; SP/CP
    // require a case-insensitive name match within the same category.
    final directory = await StorageService.getMasterStaffDirectory();
    String normName(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    String normCategory(String value) {
      final v = value.trim().toLowerCase();
      if (v == 'sp') return 'sp';
      if (v == 'cp') return 'cp';
      return 'boy';
    }
    for (final staff in [...bList, ...sList, ...cList]) {
      final role = normCategory(staff.role);
      final match = directory.where((saved) {
        if (normCategory(saved['category']?.toString() ?? 'boy') != role) return false;
        if (normName(saved['name']?.toString() ?? '') != normName(staff.name)) return false;
        if (role == 'boy') {
          return StorageService.normalizePhone(saved['phone']?.toString() ?? '') ==
              StorageService.normalizePhone(staff.phone) && staff.phone.trim().isNotEmpty;
        }
        return true;
      }).toList();
      // Never apply an ambiguous match (duplicate SP/CP names).
      if (match.length == 1) {
        final wage = (match.first['defaultWage'] as num?)?.toDouble();
        if (wage != null) staff.suggestedWage = wage;
      }
    }
    if (!mounted) return;
    widget.onListParsed(bList, sList, cList);
    setState(() {});
  }

  Future<void> _showManpowerDirectory() async {
    final staff = await StorageService.getMasterStaffDirectory();
    if (!mounted) return;
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Manpower directory'),
      content: SizedBox(width: 380, child: staff.isEmpty
        ? const Text('No saved manpower yet. Add staff in Other → Overview → Manpower.')
        : ListView.separated(shrinkWrap: true, itemCount: staff.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (ctx, i) {
          final row = staff[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${row['category'] ?? 'BOY'} · ${row['phone'] ?? ''}'),
            trailing: Text('₹${((row['defaultWage'] as num?) ?? 430).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          );
        })),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ElevatedButton(
          onPressed: () {
            var updated = 0;
            for (final item in [...widget.boysList, ...widget.spList, ...widget.cpList]) {
              final wage = item.suggestedWage;
              if (wage != null) {
                item.wage = wage;
                item.suggestedWage = null;
                updated++;
              }
            }
            Navigator.pop(ctx);
            widget.onDataChanged();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(updated == 0
                  ? 'No matching staff wages found. Existing wages were unchanged.'
                  : 'Updated wages for $updated matching staff.'),
              ));
            }
          },
          child: const Text('Done'),
        ),
      ],
    ));
  }

  void _showAddListDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Paste WhatsApp List', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          maxLines: 9,
          style: const TextStyle(fontSize: 13, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Paste staff list from WhatsApp here...',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
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
              if (ctrl.text.trim().isNotEmpty) {
                _parseListInput(ctrl.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: const Text('Load List', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddExtraStaffDialog(String role) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Extra ${role == 'boy' ? 'Boy' : (role == 'sp' ? 'SP' : 'CP')}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Name',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone (optional)',
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
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  if (role == 'boy') {
                    int nextIdx = widget.boysList.length + 1;
                    widget.boysList.add(StaffItem(
                      index: nextIdx,
                      name: name,
                      phone: phoneCtrl.text.trim(),
                      role: 'boy',
                    ));
                  } else if (role == 'sp') {
                    int nextIdx = widget.spList.length + 1;
                    widget.spList.add(StaffItem(
                      index: nextIdx,
                      name: name,
                      phone: phoneCtrl.text.trim(),
                      role: 'sp',
                    ));
                  } else if (role == 'cp') {
                    int nextIdx = widget.cpList.length + 1;
                    widget.cpList.add(StaffItem(
                      index: nextIdx,
                      name: name,
                      phone: phoneCtrl.text.trim(),
                      role: 'cp',
                    ));
                  }
                });
                widget.onDataChanged();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _editNamePhoneDialog(StaffItem item) {
    final nameCtrl = TextEditingController(text: item.name);
    final phoneCtrl = TextEditingController(text: item.phone);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit #${item.index} Details', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Name',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone',
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
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  item.name = nameCtrl.text.trim();
                  item.phone = phoneCtrl.text.trim();
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

  // Quick Select Boxes: 440, 450, 460
  void _editStaffWageDialog(StaffItem item) {
    final wageCtrl = TextEditingController(text: item.wage.toInt().toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Wage for #${item.index} ${item.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Select:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            // 3 Quick Options: 440, 450, 460
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
              'Or Custom Wage:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: wageCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter wage amount',
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
              if (w != null && w >= 0) {
                setState(() {
                  item.wage = w;
                });
                widget.onDataChanged();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmNewWorkDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Start New Work?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
          'Existing bills are securely archived in the Calendar. Ready to start a fresh staff roster?',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onStartNewWork();
            },
            child: const Text('Start Fresh', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData = widget.boysList.isNotEmpty || widget.spList.isNotEmpty || widget.cpList.isNotEmpty;
    final int totalStaff = widget.boysList.length + widget.spList.length + widget.cpList.length;
    final int presentCount = [
      ...widget.boysList,
      ...widget.spList,
      ...widget.cpList,
    ].where((s) => s.isPresent).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reporting',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
            ),
            Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 10),
                SizedBox(width: 4),
                Text(
                  'Auto-saving changes',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_2_outlined, color: Colors.white, size: 21),
            tooltip: 'Manpower directory and saved wages',
            onPressed: _showManpowerDirectory,
          ),
          if (hasData)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
              tooltip: 'New Work',
              onPressed: _confirmNewWorkDialog,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primarySurface,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
              icon: const Icon(Icons.paste_rounded, size: 15),
              label: Text(
                hasData ? 'New List' : 'Add List',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              onPressed: _showAddListDialog,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !hasData
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.groups_rounded, size: 48, color: AppColors.primary),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'No Staff Roster Loaded',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Paste your staff list directly from WhatsApp to get started with attendance and calculations.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 22),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.paste_rounded, color: Colors.white, size: 17),
                        label: const Text(
                          'Add WhatsApp Staff List',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        onPressed: _showAddListDialog,
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$totalStaff Staff Members',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$presentCount Present',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.dangerLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${totalStaff - presentCount} Absent',
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    color: const Color(0xFFF1F5F9),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'STAFF NAME & PHONE',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: AppColors.textSecondary, letterSpacing: 0.3),
                          ),
                        ),
                        SizedBox(
                          width: 34,
                          child: Center(
                            child: Text(
                              'ATT',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 48,
                          child: Center(
                            child: Text(
                              'TA (₹)',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: AppColors.success),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 48,
                          child: Center(
                            child: Text(
                              'WAGE',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: AppColors.primary),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 52,
                          child: Center(
                            child: Text(
                              'DEDUCT',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: AppColors.danger),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (widget.boysList.isNotEmpty) ...[
                          _buildSectionHeader('BOYS (${widget.boysList.length})', AppColors.primary, 'Tap name to edit details'),
                          _buildStaffCard(widget.boysList),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _showAddExtraStaffDialog('boy'),
                              icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                              label: const Text(
                                '+ Add Extra Boy',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primary),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (widget.spList.isNotEmpty) ...[
                          _buildSectionHeader('SUPERVISORS (SP)', AppColors.roleSp, null),
                          _buildStaffCard(widget.spList),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _showAddExtraStaffDialog('sp'),
                              icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.roleSp),
                              label: const Text(
                                '+ Add Extra SP',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.roleSp),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (widget.cpList.isNotEmpty) ...[
                          _buildSectionHeader('CAPTAINS (CP)', AppColors.roleCp, null),
                          _buildStaffCard(widget.cpList),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _showAddExtraStaffDialog('cp'),
                              icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.roleCp),
                              label: const Text(
                                '+ Add Extra CP',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.roleCp),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: const Border(top: BorderSide(color: AppColors.border)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                        label: const Text(
                          'Proceed to Outing Billing',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          widget.onSubmitToOuting();
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.3),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(List<StaffItem> list) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: list
              .map((item) => StaffRowItem(
                    key: ValueKey(item.index),
                    item: item,
                    onDataChanged: widget.onDataChanged,
                    onEditDetails: () => _editNamePhoneDialog(item),
                    onEditWage: () => _editStaffWageDialog(item),
                  ))
              .toList(),
        ),
      ),
    );
  }
}