import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/calculation_model.dart';

class CalculationPdfService {
  static Future<void> export(EventSettlement settlement) async {
    final pdf = pw.Document();
    pw.Font regular;
    pw.Font bold;
    var hasNotoSans = false;
    try {
      regular = await PdfGoogleFonts.notoSansRegular();
      bold = await PdfGoogleFonts.notoSansBold();
      hasNotoSans = true;
    } catch (_) {
      regular = pw.Font.helvetica();
      bold = pw.Font.helveticaBold();
    }
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final navy = PdfColor.fromHex('#172A3A');
    final muted = PdfColor.fromHex('#526777');
    final light = PdfColor.fromHex('#F1F5F9');
    final border = PdfColor.fromHex('#E2E8F0');
    final gold = PdfColor.fromHex('#B08D57');
    final currency = hasNotoSans ? '₹' : 'Rs.';
    String money(num amount) => '$currency ${NumberFormat('#,##,##0.##').format(amount)}';
    final date = DateFormat('dd/MM/yyyy').format(DateTime.tryParse(settlement.eventDate) ?? DateTime.now());
    final sp = settlement.allowances.where((a) => a.role.toLowerCase() == 'sp').toList();
    final cp = settlement.allowances.where((a) => a.role.toLowerCase() == 'cp').toList();

    pw.Widget sectionTitle(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      color: navy,
      child: pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
    );
    pw.Widget headerCell(String value) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(value, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: muted)),
    );
    pw.Widget cell(String value, {bool boldText = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(value, textAlign: align, style: pw.TextStyle(fontSize: 8, fontWeight: boldText ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
    pw.Widget staffTable(List<StaffAllowance> rows) => pw.Table(
      border: pw.TableBorder.all(color: border, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(2.6), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1.8), 4: pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: light), children: [headerCell('STAFF NAME'), headerCell('BASE PAY'), headerCell('EXTRA'), headerCell('SOURCE / TAG'), headerCell('FINAL')]),
        ...rows.map((row) => pw.TableRow(children: [
          cell(row.staffName),
          cell(money(row.basePay), align: pw.TextAlign.right),
          cell(money(row.amount), align: pw.TextAlign.right),
          cell('${row.sourceCategory}${row.auditTag.isEmpty ? '' : '\n${row.auditTag}'}'),
          cell(money(row.finalTotal), boldText: true, align: pw.TextAlign.right),
        ])),
        if (rows.isEmpty) pw.TableRow(children: [cell('No settlement rows'), cell('-'), cell('-'), cell('-'), cell('-')]),
      ],
    );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Expanded(child: pw.Text((settlement.auditoriumName.isEmpty ? 'STAFF SETTLEMENT' : settlement.auditoriumName).toUpperCase(), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: navy, letterSpacing: 0.4))),
            pw.SizedBox(width: 12),
            pw.Text('DATE  $date', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: muted)),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(height: 2, color: navy),
          pw.Container(height: 1, color: gold, margin: const pw.EdgeInsets.only(top: 2, bottom: 8)),
          pw.Text('STAFF BILLING PLATFORM  •  SP & CP SETTLEMENT', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: muted)),
          if (settlement.auditorIdentifier.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Auditor: ${settlement.auditorIdentifier}', style: pw.TextStyle(fontSize: 9, color: muted))),
        ]),
        pw.SizedBox(height: 14),
        sectionTitle('SP SETTLEMENT'),
        staffTable(sp),
        pw.SizedBox(height: 12),
        sectionTitle('CP SETTLEMENT'),
        staffTable(cp),
        pw.SizedBox(height: 14),
        sectionTitle('EXPENSE BALANCING'),
        pw.Table(border: pw.TableBorder.all(color: border, width: 0.5), children: [
          pw.TableRow(decoration: pw.BoxDecoration(color: light), children: [headerCell('LEDGER'), headerCell('ORIGINAL'), headerCell('DEDUCTED'), headerCell('REMAINING')]),
          pw.TableRow(children: [cell('Other Expenses'), cell(money(settlement.originalOtherExpenses)), cell(money(settlement.otherDeductions)), cell(money(settlement.remainingOther), boldText: true)]),
          pw.TableRow(children: [cell('Setting Bill'), cell(money(settlement.originalSettingBill)), cell(money(settlement.settingDeductions)), cell(money(settlement.remainingSetting), boldText: true)]),
        ]),
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: light, border: pw.Border.all(color: border)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('GRAND TOTALS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: navy)),
            pw.SizedBox(height: 7),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Base pay'), pw.Text(money(settlement.totalBasePay))]),
            pw.SizedBox(height: 4),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Extra allowances'), pw.Text(money(settlement.totalAllowances))]),
            pw.Divider(color: border),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Total disbursed', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(money(settlement.totalDisbursed), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
            pw.SizedBox(height: 4),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Retained expense balance'), pw.Text(money(settlement.remainingOther + settlement.remainingSetting), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
          ]),
        ),
        pw.SizedBox(height: 32),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Container(height: 0.7, color: muted), pw.SizedBox(height: 5), pw.Text('Supervisor signature', style: const pw.TextStyle(fontSize: 8))])), pw.SizedBox(width: 30), pw.Expanded(child: pw.Column(children: [pw.Container(height: 0.7, color: muted), pw.SizedBox(height: 5), pw.Text('Auditor signature', style: const pw.TextStyle(fontSize: 8))]))]),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }
}
