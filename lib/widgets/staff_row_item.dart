import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/staff_item.dart';

class StaffRowItem extends StatefulWidget {
  final StaffItem item;
  final VoidCallback onDataChanged;
  final VoidCallback onEditDetails;
  final VoidCallback onEditWage;

  const StaffRowItem({
    Key? key,
    required this.item,
    required this.onDataChanged,
    required this.onEditDetails,
    required this.onEditWage,
  }) : super(key: key);

  @override
  State<StaffRowItem> createState() => _StaffRowItemState();
}

class _StaffRowItemState extends State<StaffRowItem> {
  late TextEditingController _taCtrl;
  late TextEditingController _minusCtrl;

  @override
  void initState() {
    super.initState();
    _taCtrl = TextEditingController(
      text: widget.item.baseTa > 0 ? (widget.item.baseTa % 1 == 0 ? widget.item.baseTa.toInt().toString() : widget.item.baseTa.toString()) : '',
    );
    _minusCtrl = TextEditingController(
      text: widget.item.minusAmount > 0 ? (widget.item.minusAmount % 1 == 0 ? widget.item.minusAmount.toInt().toString() : widget.item.minusAmount.toString()) : '',
    );
  }

  @override
  void didUpdateWidget(covariant StaffRowItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentTa = widget.item.baseTa > 0 ? (widget.item.baseTa % 1 == 0 ? widget.item.baseTa.toInt().toString() : widget.item.baseTa.toString()) : '';
    if (_taCtrl.text != currentTa && (double.tryParse(_taCtrl.text) ?? 0) != widget.item.baseTa) {
      _taCtrl.text = currentTa;
    }

    final currentMinus = widget.item.minusAmount > 0 ? (widget.item.minusAmount % 1 == 0 ? widget.item.minusAmount.toInt().toString() : widget.item.minusAmount.toString()) : '';
    if (_minusCtrl.text != currentMinus && (double.tryParse(_minusCtrl.text) ?? 0) != widget.item.minusAmount) {
      _minusCtrl.text = currentMinus;
    }
  }

  @override
  void dispose() {
    _taCtrl.dispose();
    _minusCtrl.dispose();
    super.dispose();
  }

  void _cycleAttendance() {
    setState(() {
      if (widget.item.attendance == '') {
        widget.item.attendance = '✅';
      } else if (widget.item.attendance == '✅') {
        widget.item.attendance = '🔴';
      } else {
        widget.item.attendance = '';
      }
    });
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bool isAbsent = widget.item.attendance == '🔴';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          // Name & Phone
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: widget.onEditDetails,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${widget.item.index}. ${widget.item.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            color: isAbsent ? AppColors.textMuted : AppColors.textPrimary,
                            decoration: isAbsent ? TextDecoration.lineThrough : TextDecoration.none,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_rounded, size: 11, color: Colors.grey.shade400),
                    ],
                  ),
                  if (widget.item.phone.isNotEmpty)
                    Text(
                      widget.item.phone,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  if (widget.item.suggestedWage != null)
                    InkWell(
                      onTap: () {
                        setState(() {
                          widget.item.wage = widget.item.suggestedWage!;
                          widget.item.suggestedWage = null;
                        });
                        widget.onDataChanged();
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3C4),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFFE8C65A)),
                        ),
                        child: Text(
                          'Set ₹${widget.item.suggestedWage!.toStringAsFixed(widget.item.suggestedWage! % 1 == 0 ? 0 : 2)}',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF805B00)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Attendance Selector
          GestureDetector(
            onTap: _cycleAttendance,
            child: Container(
              width: 34,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.item.attendance == '✅'
                    ? AppColors.successLight
                    : (isAbsent ? AppColors.dangerLight : const Color(0xFFF8FAFC)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.item.attendance == '✅'
                      ? const Color(0xFF86EFAC)
                      : (isAbsent ? const Color(0xFFFCA5A5) : AppColors.border),
                ),
              ),
              child: widget.item.attendance.isEmpty
                  ? const Text('—', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.bold))
                  : Text(widget.item.attendance, style: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),

          // TA Input
          SizedBox(
            width: 48,
            height: 32,
            child: TextField(
              controller: _taCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (val) {
                widget.item.baseTa = double.tryParse(val.trim()) ?? 0.0;
                if (widget.item.attendance == '' && widget.item.baseTa > 0) {
                  setState(() => widget.item.attendance = '✅');
                }
                widget.onDataChanged();
              },
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success),
              decoration: InputDecoration(
                hintText: 'TA',
                hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                isDense: true,
                filled: true,
                fillColor: widget.item.baseTa > 0 ? AppColors.successLight.withOpacity(0.4) : const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.item.baseTa > 0 ? const Color(0xFF86EFAC) : AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.success, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Wage Button
          SizedBox(
            width: 48,
            height: 32,
            child: InkWell(
              onTap: widget.onEditWage,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Text(
                  '${widget.item.wage.toInt()}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Deduction / Minus Input
          SizedBox(
            width: 52,
            height: 32,
            child: TextField(
              controller: _minusCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (val) {
                widget.item.minusAmount = double.tryParse(val.trim()) ?? 0.0;
                if (widget.item.attendance == '' && widget.item.minusAmount > 0) {
                  setState(() => widget.item.attendance = '✅');
                }
                widget.onDataChanged();
              },
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.danger),
              decoration: InputDecoration(
                hintText: '−₹',
                hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                isDense: true,
                filled: true,
                fillColor: widget.item.minusAmount > 0 ? AppColors.dangerLight.withOpacity(0.4) : const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.item.minusAmount > 0 ? const Color(0xFFFCA5A5) : AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}