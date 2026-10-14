import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import '../constants/app_colors.dart';
import '../models/catering_bill.dart';
import '../services/storage_service.dart';

class CalendarScreen extends StatefulWidget {
  final Function(CateringBill) onSelectBill;
  const CalendarScreen({Key? key, required this.onSelectBill}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime selectedMonth = DateTime.now();
  DateTime selectedDate = DateTime.now();
  List<CateringBill> allBills = [];
  bool isLoading = true;
  bool isBackupProcessing = false;

  @override
  void initState() {
    super.initState();
    _fetchBills();
    StorageService.dataRevision.addListener(_onRestoredDataChanged);
  }

  void _onRestoredDataChanged() { _fetchBills(); }

  @override
  void dispose() {
    StorageService.dataRevision.removeListener(_onRestoredDataChanged);
    super.dispose();
  }

  Future<void> _fetchBills() async {
    final bills = await StorageService.getAllBills();
    if (mounted) {
      setState(() {
        allBills = bills;
        isLoading = false;
      });
    }
  }

  List<CateringBill> get billsForSelectedDate {
    return allBills.where((b) {
      return b.date.year == selectedDate.year &&
          b.date.month == selectedDate.month &&
          b.date.day == selectedDate.day;
    }).toList();
  }

  Future<void> _saveLocalBackup() async {
    setState(() => isBackupProcessing = true);
    try {
      final jsonStr = await StorageService.exportBackupJson();
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await FileSaver.instance.saveFile(
        name: 'staff_billing_backup_$stamp',
        bytes: bytes,
        ext: 'json',
        mimeType: MimeType.json,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSON backup exported. Choose Downloads or Google Drive if your device offers that location.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup export failed: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => isBackupProcessing = false);
    }
  }

  Future<void> _restoreLocalBackup() async {
    setState(() => isBackupProcessing = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw Exception('The selected JSON file could not be read.');
      final success = await StorageService.restoreBackupJson(utf8.decode(bytes));
      if (!success) throw Exception('Invalid or unsupported backup JSON file.');
      await _fetchBills();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored. All open screens are refreshing from the restored data.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => isBackupProcessing = false);
    }
  }

  void _showLocalBackupRestoreDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_sync_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('JSON Backup / Restore', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Export a JSON backup file, then save it in Downloads or Google Drive. To recover data, choose the saved JSON file with Restore.',
          style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.file_upload_outlined, color: AppColors.success, size: 18),
            label: const Text('Export backup file', style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () {
              Navigator.pop(ctx);
              _saveLocalBackup();
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.folder_open_outlined, color: Colors.white, size: 18),
            label: const Text('Choose JSON to restore', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _restoreLocalBackup();
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBill(CateringBill b) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Event Bill?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'Are you sure you want to delete "${b.auditoriumName.isEmpty ? 'Catering Event' : b.auditoriumName}"? This action cannot be reversed.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.deleteBill(b.id);
              _fetchBills();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
    final firstDayWeekday = DateTime(selectedMonth.year, selectedMonth.month, 1).weekday; // 1 = Mon, 7 = Sun
    final weekHeaders = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Event Calendar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
        actions: [
          if (isBackupProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_rounded, color: Colors.white, size: 22),
              tooltip: 'Local backup and restore',
              onPressed: _showLocalBackupRestoreDialog,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            onPressed: _fetchBills,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Monthly Calendar Card
                        Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Month Header
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                                    onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1)),
                                  ),
                                  Text(
                                    DateFormat('MMMM yyyy').format(selectedMonth),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right_rounded, size: 22),
                                    onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1)),
                                  ),
                                ],
                              ),
                            ),

                            // Weekday Headers
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: weekHeaders
                                    .map(
                                      (d) => SizedBox(
                                        width: 32,
                                        child: Center(
                                          child: Text(
                                            d,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.textMuted),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const Divider(height: 1, color: AppColors.borderSubtle),

                            // Day Cells Grid (Fixed height per row)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisExtent: 44, // Overflow ozhivakkaan fixed cell height
                                ),
                                itemCount: daysInMonth + (firstDayWeekday - 1),
                                itemBuilder: (context, index) {
                                  if (index < firstDayWeekday - 1) return const SizedBox.shrink();
                                  final day = index - (firstDayWeekday - 2);
                                  final cellDate = DateTime(selectedMonth.year, selectedMonth.month, day);
                                  final hasBills = allBills.any((b) =>
                                      b.date.year == cellDate.year &&
                                      b.date.month == cellDate.month &&
                                      b.date.day == cellDate.day);
                                  final isSelected = cellDate.year == selectedDate.year &&
                                      cellDate.month == selectedDate.month &&
                                      cellDate.day == selectedDate.day;

                                  return InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => setState(() => selectedDate = cellDate),
                                    child: Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppColors.primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '$day',
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                              fontSize: 12,
                                              color: isSelected ? Colors.white : AppColors.textPrimary,
                                            ),
                                          ),
                                          if (hasBills)
                                            Container(
                                              margin: const EdgeInsets.only(top: 3),
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isSelected ? const Color(0xFF38BDF8) : AppColors.success,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Selected Date Event Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('dd MMMM yyyy').format(selectedDate),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.textPrimary),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: billsForSelectedDate.isEmpty ? const Color(0xFFF1F5F9) : AppColors.successLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                billsForSelectedDate.isEmpty
                                    ? 'No Events'
                                    : '${billsForSelectedDate.length} ${billsForSelectedDate.length == 1 ? 'Event' : 'Events'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: billsForSelectedDate.isEmpty ? AppColors.textSecondary : AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Event Cards List for Selected Date
                      if (billsForSelectedDate.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_busy_rounded, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  'No bills recorded for this date',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                          itemCount: billsForSelectedDate.length,
                          itemBuilder: (context, index) {
                            final b = billsForSelectedDate[index];
                            final double totBill = b.getAllTotalBill(b.taMultiplier);
                            final double totTa = b.getAllTotalTa(b.taMultiplier);
                            final int presentCount = b.staffList.where((s) => s.isPresent).length;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => widget.onSelectBill(b),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                b.auditoriumName.isEmpty ? 'Catering Event' : b.auditoriumName,
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                                              onPressed: () => _confirmDeleteBill(b),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.people_alt_outlined, size: 14, color: AppColors.textSecondary),
                                            const SizedBox(width: 5),
                                            Text(
                                              '${b.staffList.length} Staff • $presentCount Present',
                                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        const Divider(height: 1, color: AppColors.borderSubtle),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Total Bill: ₹${totBill.toInt()}',
                                                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppColors.primary),
                                                ),
                                                Text(
                                                  'TA: ₹${totTa.toInt()}',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: const [
                                                Text(
                                                  'View Details',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                                                ),
                                                SizedBox(width: 4),
                                                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.primary),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}