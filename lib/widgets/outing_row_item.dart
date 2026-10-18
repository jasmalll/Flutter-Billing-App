import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/staff_item.dart';

class OutingRowItem extends StatelessWidget {
  final StaffItem item;
  final double multiplier;
  final VoidCallback onDataChanged;
  final VoidCallback onEditWage;

  const OutingRowItem({
    Key? key,
    required this.item,
    required this.multiplier,
    required this.onDataChanged,
    required this.onEditWage,
  }) : super(key: key);

  void _cycleOutingStatus() {
    if (item.outingStatus.isEmpty) {
      item.outingStatus = '✅';
    } else if (item.outingStatus == '✅') {
      item.outingStatus = '❎';
    } else {
      item.outingStatus = '';
    }
    onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (!item.isPresent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: AppColors.dangerLight.withOpacity(0.4),
        child: Row(
          children: [
            Text('${item.index}. ${item.name}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textMuted)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.dangerLight, borderRadius: BorderRadius.circular(4)),
              child: const Text('🔴 Absent', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 11)),
            ),
          ],
        ),
      );
    }

    double autoTa = item.getCalculatedTa(multiplier);
    double total = item.getTotal(multiplier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          // Staff Details
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.index}. ${item.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.phone.isNotEmpty)
                  Text(item.phone, style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary)),
                const SizedBox(height: 2),

                // Calculation Breakdown Equation
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InkWell(
                      onTap: onEditWage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                        ),
                        child: Text(
                          '₹${item.wage.toInt()}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ),
                    ),
                    if (item.minusAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '− ₹${item.minusAmount.toInt()}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.danger),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        onTap: onEditWage,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF86EFAC), width: 0.8),
                          ),
                          child: Text(
                            '+ ₹${autoTa.toInt()} TA ✎',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.success),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Total Amount
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '= ₹${total.toInt()}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: AppColors.primary),
            ),
          ),

          // Outing Verification Status Button
          GestureDetector(
            onTap: _cycleOutingStatus,
            child: Container(
              width: 32,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.outingStatus == '✅'
                    ? AppColors.successLight
                    : (item.outingStatus == '❎' ? AppColors.dangerLight : const Color(0xFFF8FAFC)),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: item.outingStatus == '✅'
                      ? const Color(0xFF86EFAC)
                      : (item.outingStatus == '❎' ? const Color(0xFFFCA5A5) : AppColors.border),
                ),
              ),
              child: Text(
                item.outingStatus.isEmpty ? '—' : item.outingStatus,
                style: TextStyle(
                  fontSize: item.outingStatus.isEmpty ? 11 : 12,
                  fontWeight: FontWeight.bold,
                  color: item.outingStatus.isEmpty ? AppColors.textMuted : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}