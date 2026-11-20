import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const violet = Color(0xFF8861F4);
const gain = Color(0xFF16B887);
const loss = Color(0xFFF35D78);
final rupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
String cash(int paise) => rupees.format(paise / 100);
int? amountToPaise(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', ''));
  if (value == null || !value.isFinite || value <= 0 || value > 1000000000) return null;
  return (value * 100).round();
}
String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class LedgerEntry {
  final String id, friend, type, note;
  final int amount;
  final DateTime date;
  const LedgerEntry({required this.id, required this.friend, required this.type,
    required this.note, required this.amount, required this.date});
  int get signed => type == 'Profit' ? amount : -amount;
  Map<String, dynamic> toJson() => {
    'id': id, 'friend': friend, 'type': type, 'note': note,
    'amount': amount, 'date': date.toIso8601String(),
  };
  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    id: '${j['id'] ?? ''}', friend: '${j['friend'] ?? ''}',
    type: '${j['type'] ?? j['kind'] ?? 'Profit'}',
    note: '${j['note'] ?? ''}',
    amount: (j['amount'] as num?)?.toInt() ?? (j['paise'] as num?)?.toInt() ?? 0,
    date: DateTime.tryParse('${j['date']}') ?? DateTime.now(),
  );
}

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const LedgerApp()); }
class LedgerApp extends StatefulWidget {
  const LedgerApp({super.key});
  @override State<LedgerApp> createState() => _LedgerAppState();
}
class _LedgerAppState extends State<LedgerApp> {
  bool dark = true;
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'Trade Ledger Pro',
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: violet,
      scaffoldBackgroundColor: const Color(0xFFF5F6FB),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)))),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorSchemeSeed: violet, scaffoldBackgroundColor: const Color(0xFF0D1020),
      cardTheme: CardThemeData(color: const Color(0xFF1B2035), elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)))),
    home: LedgerHome(dark: dark, toggleTheme: () => setState(() => dark = !dark)),
  );
}
class LedgerHome extends StatefulWidget {
  final bool dark;
  final VoidCallback toggleTheme;
  const LedgerHome({super.key, required this.dark, required this.toggleTheme});
  @override State<LedgerHome> createState() => _LedgerHomeState();
}
class _LedgerHomeState extends State<LedgerHome> {
  List<LedgerEntry> entries = [];
  List<String> friends = [];
  int tab = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime tradeMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool loaded = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      // A fresh date-wise ledger. Old category data is intentionally not imported.
      final raw = p.getString('ledger_v23_entries');
      final people = p.getString('ledger_v23_friends');
      if (!mounted) return;
      setState(() {
        entries = raw == null ? [] : (jsonDecode(raw) as List)
          .map((e) => LedgerEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        friends = people == null ? [] : List<String>.from(jsonDecode(people) as List);
        loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loaded = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved data could not be loaded. Existing storage was not changed.')));
    }
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ledger_v23_entries', jsonEncode(entries.map((e) => e.toJson()).toList()));
    await p.setString('ledger_v23_friends', jsonEncode(friends));
  }
  List<LedgerEntry> get personal => entries.where((e) => e.friend.isEmpty).toList();
  int net(Iterable<LedgerEntry> list) => list.fold(0, (v, e) => v + e.signed);
  int profits(Iterable<LedgerEntry> list) => list.where((e) => e.type == 'Profit').fold(0, (v, e) => v + e.amount);
  int losses(Iterable<LedgerEntry> list) => list.where((e) => e.type == 'Loss').fold(0, (v, e) => v + e.amount);
  int charges(Iterable<LedgerEntry> list) => list.where((e) => e.type == 'Charges').fold(0, (v, e) => v + e.amount);
  int get tradingDays => personal.map((e) => dateKey(e.date)).toSet().length;
  Color valueColor(int n) => n < 0 ? loss : n > 0 ? gain : violet;
  bool inMonth(LedgerEntry e, DateTime m) => e.date.year == m.year && e.date.month == m.month;
  void toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<bool> confirm(String message) async => await showDialog<bool>(context: context,
    builder: (c) => AlertDialog(title: Text(message), content: const Text('This cannot be undone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))])) ?? false;

  Future<void> editEntry({String friend = '', LedgerEntry? old}) async {
    final amount = TextEditingController(text: old == null ? '' : (old.amount / 100).toStringAsFixed(2));
    final note = TextEditingController(text: old?.note ?? '');
    String type = old?.type ?? 'Profit';
    DateTime date = old?.date ?? DateTime.now();
    final result = await showModalBottomSheet<LedgerEntry>(context: context,
      isScrollControlled: true, showDragHandle: true,
      builder: (sheet) => StatefulBuilder(builder: (c, update) => Padding(
        padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.viewInsetsOf(c).bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(old == null ? (friend.isEmpty ? 'Add Daily P&L' : 'Add $friend Entry') : 'Edit Entry',
            style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          SegmentedButton<String>(segments: (friend.isEmpty ? ['Profit', 'Loss'] : ['Profit', 'Loss', 'Charges'])
            .map((t) => ButtonSegment(value: t, label: Text(t))).toList(),
            selected: {type}, onSelectionChanged: (s) => update(() => type = s.first)),
          const SizedBox(height: 18),
          TextField(controller: amount, autofocus: old == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee), border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: note, decoration: const InputDecoration(
            labelText: 'Notes (optional)', prefixIcon: Icon(Icons.edit_note), border: OutlineInputBorder())),
          const SizedBox(height: 14),
          OutlinedButton.icon(icon: const Icon(Icons.calendar_month_outlined),
            label: Text(DateFormat('EEE, dd MMM yyyy').format(date)), onPressed: () async {
              final chosen = await showDatePicker(context: c, initialDate: date,
                firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (chosen != null) update(() => date = chosen);
            }),
          const SizedBox(height: 16),
          FilledButton(onPressed: () {
            final n = amountToPaise(amount.text);
            if (n == null) {
              ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Enter a valid amount greater than zero')));
              return;
            }
            Navigator.pop(c, LedgerEntry(id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
              friend: friend, type: type, note: note.text.trim(), amount: n, date: date));
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('Save Entry'))),
        ])))));
    amount.dispose(); note.dispose();
    if (result == null || !mounted) return;
    setState(() { if (old != null) entries.removeWhere((e) => e.id == old.id); entries.add(result); });
    await save();
  }
  Future<void> removeEntry(LedgerEntry e) async {
    if (!await confirm('Delete this entry?') || !mounted) return;
    setState(() => entries.removeWhere((x) => x.id == e.id));
    await save();
  }
  Future<void> addFriend() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('Add Friend'), content: TextField(controller: controller,
        autofocus: true, textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Friend name')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Add'))]));
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    if (friends.any((f) => f.toLowerCase() == name.toLowerCase())) { toast('Friend already exists'); return; }
    setState(() => friends.add(name)); await save();
  }
  Future<void> removeFriend(String f) async {
    if (!await confirm('Remove $f and all their entries?') || !mounted) return;
    setState(() { friends.remove(f); entries.removeWhere((e) => e.friend == f); });
    await save();
  }
  Future<void> exportPdf({String? friend}) async {
    final rows = entries.where((e) => friend == null ? e.friend.isEmpty : e.friend == friend).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final totalProfit = profits(rows);
    final totalLoss = losses(rows);
    final totalCharges = charges(rows);
    final overall = net(rows);
    final greenPdf = PdfColor.fromHex('#11865E');
    final redPdf = PdfColor.fromHex('#C7354C');
    final mutedPdf = PdfColor.fromHex('#576176');
    final inkPdf = PdfColor.fromHex('#19243B');
    final lightPdf = PdfColor.fromHex('#F3F5FA');
    String inr(int paise) => 'INR ${(paise / 100).toStringAsFixed(2)}';
    pw.Widget totalLine(String label, int amount, PdfColor color, {bool bold = false}) =>
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 5), child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: pw.TextStyle(fontSize: bold ? 13 : 11,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: inkPdf)),
          pw.Text(inr(amount), style: pw.TextStyle(fontSize: bold ? 13 : 11,
            fontWeight: pw.FontWeight.bold, color: color)),
        ]));
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => pw.Align(alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: mutedPdf))),
      build: (_) => [
        pw.Text('TRADE LEDGER PRO', style: pw.TextStyle(
          fontSize: 21, fontWeight: pw.FontWeight.bold, color: inkPdf)),
        pw.SizedBox(height: 4),
        pw.Text(friend == null ? 'Personal Daily Profit & Loss Statement' : '$friend - Friend Ledger Statement',
          style: pw.TextStyle(fontSize: 12, color: mutedPdf)),
        pw.SizedBox(height: 5),
        pw.Text('Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 9, color: mutedPdf)),
        pw.SizedBox(height: 20),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E6EF'), width: .5),
          columnWidths: {
            0: const pw.FixedColumnWidth(77),
            1: const pw.FixedColumnWidth(65),
            2: const pw.FlexColumnWidth(),
            3: const pw.FixedColumnWidth(92),
          },
          children: [
            pw.TableRow(decoration: pw.BoxDecoration(color: inkPdf), children: [
              for (final h in ['Date', 'Type', 'Notes', 'Amount'])
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(h,
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 10,
                    fontWeight: pw.FontWeight.bold))),
            ]),
            ...rows.asMap().entries.map((item) {
              final e = item.value;
              final c = e.type == 'Profit' ? greenPdf : redPdf;
              pw.Widget cell(String value, {PdfColor? color, bool bold = false}) =>
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(value,
                  style: pw.TextStyle(fontSize: 9, color: color ?? inkPdf,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)));
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: item.key.isEven ? PdfColors.white : lightPdf),
                children: [
                  cell(DateFormat('dd-MM-yyyy').format(e.date)),
                  cell(e.type, color: c, bold: true),
                  cell(e.note.isEmpty ? '-' : e.note),
                  cell(inr(e.signed), color: c, bold: true),
                ]);
            }),
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Container(padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(color: lightPdf,
            borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Text('OVERALL CALCULATION', style: pw.TextStyle(fontSize: 12,
              fontWeight: pw.FontWeight.bold, color: inkPdf)),
            pw.SizedBox(height: 8),
            totalLine('Total Profit (+)', totalProfit, greenPdf),
            totalLine('Total Loss (-)', -totalLoss, redPdf),
            if (friend != null) totalLine('Total Charges (-)', -totalCharges, redPdf),
            pw.Divider(color: PdfColor.fromHex('#CDD4E1')),
            totalLine('Overall Net P&L', overall, overall < 0 ? redPdf : greenPdf, bold: true),
            pw.SizedBox(height: 4),
            pw.Text('Entries: ${rows.length}', style: pw.TextStyle(fontSize: 9, color: mutedPdf)),
          ])),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  Widget heading(String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 23, 4, 13),
    child: Row(children: [Expanded(child: Text(text, style: const TextStyle(
      fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.5))), if (action != null) action]));
  Widget stat(String label, String value, Color color) => Expanded(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color)),
      const SizedBox(height: 5), Text(label, style: TextStyle(fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]));
  Widget heroCard() {
    final total = net(personal);
    final bg = widget.dark ? const Color(0xFF22203B) : Colors.white;
    final textColor = widget.dark ? Colors.white : const Color(0xFF24233B);
    return Container(width: double.infinity, padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28),
        border: Border.all(color: valueColor(total).withValues(alpha: .28), width: 1.3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: widget.dark ? .12 : .05),
          blurRadius: 24, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text('ALL-TIME P&L', style: TextStyle(color: textColor.withValues(alpha: .75),
          fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.3)),
          const Spacer(), Icon(total < 0 ? Icons.trending_down : Icons.trending_up, color: valueColor(total))]),
        const SizedBox(height: 18),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text('${total > 0 ? '+' : ''}${cash(total)}', style: TextStyle(
            color: valueColor(total), fontSize: 37, fontWeight: FontWeight.w900))),
        const SizedBox(height: 21),
        Divider(color: textColor.withValues(alpha: .15)),
        const SizedBox(height: 13),
        Row(children: [stat('Total Profit', cash(profits(personal)), gain),
          stat('Total Loss', cash(losses(personal)), loss),
          stat('Trading Days', '$tradingDays', textColor)]),
      ]));
  }
  DateTime get monday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }
  Widget weeklyDays() {
    final start = monday;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: List.generate(7, (i) {
      final d = start.add(Duration(days: i));
      final dayRows = personal.where((e) => dateKey(e.date) == dateKey(d));
      final value = net(dayRows);
      final active = dayRows.isNotEmpty;
      return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(children: [
          SizedBox(width: 43, height: 43, child: CustomPaint(
            painter: RingPainter(color: active ? valueColor(value) : Colors.grey, active: active),
            child: Center(child: Icon(active ? (value < 0 ? Icons.south_east : Icons.north_east)
              : Icons.remove, size: 18, color: active ? valueColor(value) : Colors.grey)))),
          const SizedBox(height: 8),
          Text(DateFormat('EEE').format(d), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, child: Text(active ? cash(value) : '—',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: active ? valueColor(value) : Theme.of(context).colorScheme.onSurfaceVariant))),
        ])));
    }));
  }
  Widget monthCard() {
    final rows = personal.where((e) => inMonth(e, month)).toList();
    final p = profits(rows), l = losses(rows);
    final total = p + l;
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
      Row(children: [IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
        icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text(DateFormat('MMMM yyyy').format(month), textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_right))]),
      const SizedBox(height: 12),
      SizedBox(height: 142, width: 142, child: CustomPaint(
        painter: DonutPainter(profit: p, loss: l),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('NET P&L', style: TextStyle(fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown, child: Text(cash(p - l),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: valueColor(p - l)))),
        ]))),
      const SizedBox(height: 18),
      Row(children: [stat('Profit', cash(p), gain), stat('Loss', cash(l), loss)]),
      if (total == 0) const Padding(padding: EdgeInsets.only(top: 12),
        child: Text('No entries this month', style: TextStyle(fontSize: 12))),
    ])));
  }
  Widget homePage() => ListView(padding: const EdgeInsets.fromLTRB(17, 12, 17, 115), children: [
    heroCard(),
    heading('This Week'),
    Card(child: Padding(padding: const EdgeInsets.fromLTRB(11, 22, 11, 22), child: weeklyDays())),
    heading('Monthly P&L'),
    monthCard(),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: () => editEntry(), icon: const Icon(Icons.add),
      label: const Padding(padding: EdgeInsets.all(10), child: Text('Add Profit / Loss'))),
  ]);
  Widget entryTile(LedgerEntry e) => ListTile(
    leading: CircleAvatar(backgroundColor: valueColor(e.signed).withValues(alpha: .12),
      child: Icon(e.signed < 0 ? Icons.south_east : Icons.north_east, color: valueColor(e.signed))),
    title: Text(e.type, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(e.note.isEmpty ? DateFormat('dd MMM yyyy').format(e.date)
      : '${DateFormat('dd MMM yyyy').format(e.date)} • ${e.note}', maxLines: 2),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(cash(e.signed), style: TextStyle(fontWeight: FontWeight.w800, color: valueColor(e.signed))),
      PopupMenuButton<String>(onSelected: (v) => v == 'edit'
        ? editEntry(friend: e.friend, old: e) : removeEntry(e),
        itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete'))]),
    ]));
  Widget daysPage() {
    final days = <String, List<LedgerEntry>>{};
    for (final e in personal.where((e) => inMonth(e, tradeMonth))) {
      days.putIfAbsent(dateKey(e.date), () => []).add(e);
    }
    final keys = days.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 115), children: [
      heading('Trading Days', action: IconButton(onPressed: () => exportPdf(),
        icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Export PDF')),
      Card(child: Row(children: [IconButton(onPressed: () => setState(() => tradeMonth =
          DateTime(tradeMonth.year, tradeMonth.month - 1)), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text(DateFormat('MMMM yyyy').format(tradeMonth),
          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(onPressed: () => setState(() => tradeMonth =
          DateTime(tradeMonth.year, tradeMonth.month + 1)), icon: const Icon(Icons.chevron_right))])),
      const SizedBox(height: 12),
      if (keys.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(30),
        child: Text('No trading days this month. Tap + to add your first P&L.', textAlign: TextAlign.center))),
      ...keys.map((key) {
        final rows = days[key]!;
        rows.sort((a, b) => b.id.compareTo(a.id));
        final total = net(rows);
        return Card(child: ExpansionTile(
          leading: Icon(total < 0 ? Icons.trending_down : Icons.trending_up, color: valueColor(total)),
          title: Text(DateFormat('EEEE, dd MMM').format(DateTime.parse(key)),
            style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${rows.length} ${rows.length == 1 ? 'entry' : 'entries'}'),
          trailing: Text(cash(total), style: TextStyle(color: valueColor(total), fontWeight: FontWeight.w800)),
          children: rows.map(entryTile).toList()));
      }),
    ]);
  }
  Widget friendsPage() => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
    heading('Friends Ledger'),
    FilledButton.icon(onPressed: addFriend, icon: const Icon(Icons.person_add_alt_1),
      label: const Padding(padding: EdgeInsets.all(10), child: Text('Add Friend'))),
    const SizedBox(height: 15),
    if (friends.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(28),
      child: Text('Add a friend to maintain a completely separate ledger.', textAlign: TextAlign.center))),
    ...friends.map((f) {
      final rows = entries.where((e) => e.friend == f);
      final total = net(rows);
      return Card(child: ListTile(onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => FriendDetailPage(
          name: f, rows: () => entries.where((e) => e.friend == f).toList(),
          add: () async { await editEntry(friend: f); if (mounted) setState(() {}); },
          edit: (e) async { await editEntry(friend: f, old: e); if (mounted) setState(() {}); },
          delete: (e) async { await removeEntry(e); if (mounted) setState(() {}); },
          pdf: () => exportPdf(friend: f),
          remove: () async { await removeFriend(f); if (mounted) Navigator.pop(context); },
        ))),
        leading: CircleAvatar(backgroundColor: violet.withValues(alpha: .14),
          child: Text(f.substring(0, 1).toUpperCase(), style: const TextStyle(color: violet))),
        title: Text(f, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${rows.length} entries • Separate balance'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
          children: [Text(cash(total), style: TextStyle(color: valueColor(total),
            fontWeight: FontWeight.w800)), const Icon(Icons.chevron_right, size: 18)])));
    }),
  ]);
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(toolbarHeight: 77, title: const Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('जय श्री पूनरासर', style: TextStyle(color: violet, fontSize: 12,
        fontWeight: FontWeight.w800)), SizedBox(height: 4),
        Text('Trade Ledger Pro', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21))]),
      actions: [IconButton(tooltip: 'Toggle theme', onPressed: widget.toggleTheme,
        icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined))]),
    drawer: Drawer(child: SafeArea(child: ListView(children: [
      const DrawerHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('जय श्री पूनरासर', style: TextStyle(color: violet)),
        SizedBox(height: 10), Text('Trade Ledger Pro',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 23))])),
      ListTile(leading: const Icon(Icons.picture_as_pdf_outlined),
        title: const Text('Export Personal PDF'), onTap: () { Navigator.pop(context); exportPdf(); }),
      ListTile(leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('Dark / Light Theme'), onTap: () { Navigator.pop(context); widget.toggleTheme(); }),
      const ListTile(leading: Icon(Icons.info_outline), title: Text('Version 2.3')),
    ]))),
    body: !loaded ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: tab,
      children: [homePage(), daysPage(), const AverageCalculator(), friendsPage()]),
    floatingActionButton: loaded && (tab == 0 || tab == 1)
      ? FloatingActionButton(onPressed: () => editEntry(), backgroundColor: violet,
          child: const Icon(Icons.add, color: Colors.white)) : null,
    bottomNavigationBar: NavigationBar(selectedIndex: tab,
      onDestinationSelected: (i) => setState(() => tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month), label: 'Days'),
        NavigationDestination(icon: Icon(Icons.calculate_outlined),
          selectedIcon: Icon(Icons.calculate), label: 'Avg Calc'),
        NavigationDestination(icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people), label: 'Friends'),
      ]),
  );
}

class FriendDetailPage extends StatefulWidget {
  final String name;
  final List<LedgerEntry> Function() rows;
  final Future<void> Function() add;
  final Future<void> Function(LedgerEntry) edit, delete;
  final Future<void> Function() pdf, remove;
  const FriendDetailPage({super.key, required this.name, required this.rows,
    required this.add, required this.edit, required this.delete,
    required this.pdf, required this.remove});
  @override State<FriendDetailPage> createState() => _FriendDetailPageState();
}
class _FriendDetailPageState extends State<FriendDetailPage> {
  @override Widget build(BuildContext context) {
    final rows = widget.rows()..sort((a, b) => b.date.compareTo(a.date));
    final p = rows.where((e) => e.type == 'Profit').fold<int>(0, (v, e) => v + e.amount);
    final l = rows.where((e) => e.type == 'Loss').fold<int>(0, (v, e) => v + e.amount);
    final c = rows.where((e) => e.type == 'Charges').fold<int>(0, (v, e) => v + e.amount);
    final n = p - l - c;
    return Scaffold(appBar: AppBar(title: Text(widget.name), actions: [
      IconButton(tooltip: 'Export PDF', onPressed: widget.pdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
      PopupMenuButton<String>(onSelected: (v) { if (v == 'remove') widget.remove(); },
        itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove Friend'))]),
    ]), body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
      Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FRIEND BALANCE', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        FittedBox(fit: BoxFit.scaleDown, child: Text(cash(n), style: TextStyle(fontSize: 35,
          fontWeight: FontWeight.w900, color: n < 0 ? loss : gain))),
        const Divider(height: 32),
        Row(children: [Expanded(child: _mini('Profit', cash(p), gain)),
          Expanded(child: _mini('Loss', cash(l), loss)),
          Expanded(child: _mini('Charges', cash(c), loss))]),
      ]))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: () async { await widget.add(); if (mounted) setState(() {}); },
        icon: const Icon(Icons.add), label: const Padding(padding: EdgeInsets.all(11),
          child: Text('Add Profit / Loss / Charges'))),
      const Padding(padding: EdgeInsets.fromLTRB(5, 24, 5, 10), child: Text('Entry History',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
      if (rows.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24),
        child: Text('No entries yet', textAlign: TextAlign.center))),
      ...rows.map((e) => Card(child: ListTile(
        leading: Icon(e.signed < 0 ? Icons.south_east : Icons.north_east,
          color: e.signed < 0 ? loss : gain),
        title: Text(e.type, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(e.note.isEmpty ? DateFormat('dd MMM yyyy').format(e.date)
          : '${DateFormat('dd MMM yyyy').format(e.date)} • ${e.note}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(cash(e.signed), style: TextStyle(color: e.signed < 0 ? loss : gain,
            fontWeight: FontWeight.w800)),
          PopupMenuButton<String>(onSelected: (v) async {
            if (v == 'edit') { await widget.edit(e); } else { await widget.delete(e); }
            if (mounted) setState(() {});
          }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete'))]),
        ])))),
    ]));
  }
  Widget _mini(String title, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(value,
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800))),
      const SizedBox(height: 5), Text(title, style: const TextStyle(fontSize: 12)),
    ]);
}

class RingPainter extends CustomPainter {
  final Color color;
  final bool active;
  RingPainter({required this.color, required this.active});
  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 4;
    canvas.drawCircle(center, r, Paint()..color = Colors.grey.withValues(alpha: .22)
      ..style = PaintingStyle.stroke..strokeWidth = 5);
    if (active) canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2,
      math.pi * 1.6, false, Paint()..color = color..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round..strokeWidth = 5);
  }
  @override bool shouldRepaint(covariant RingPainter old) => old.color != color || old.active != active;
}
class DonutPainter extends CustomPainter {
  final int profit, loss;
  DonutPainter({required this.profit, required this.loss});
  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: r);
    final base = Paint()..color = Colors.grey.withValues(alpha: .18)
      ..strokeWidth = 13..style = PaintingStyle.stroke;
    canvas.drawCircle(center, r, base);
    final total = profit + loss;
    if (total == 0) return;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    final pAngle = 2 * math.pi * profit / total;
    if (profit > 0) canvas.drawArc(rect, -math.pi / 2, pAngle, false, paint..color = gain);
    if (loss > 0) canvas.drawArc(rect, -math.pi / 2 + pAngle, 2 * math.pi - pAngle,
      false, paint..color = loss);
  }
  @override bool shouldRepaint(covariant DonutPainter old) => old.profit != profit || old.loss != loss;
}

class AverageCalculator extends StatefulWidget {
  const AverageCalculator({super.key});
  @override State<AverageCalculator> createState() => _AverageCalculatorState();
}
class _AverageCalculatorState extends State<AverageCalculator> {
  final oldPrice = TextEditingController(), oldQty = TextEditingController();
  final newPrice = TextEditingController(), newQty = TextEditingController();
  @override void dispose() { oldPrice.dispose(); oldQty.dispose(); newPrice.dispose(); newQty.dispose(); super.dispose(); }
  Widget field(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 13), child: TextField(controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
  @override Widget build(BuildContext context) {
    final p1 = double.tryParse(oldPrice.text), q1 = double.tryParse(oldQty.text);
    final p2 = double.tryParse(newPrice.text), q2 = double.tryParse(newQty.text);
    final valid = p1 != null && p2 != null && q1 != null && q2 != null &&
      p1.isFinite && p2.isFinite && q1.isFinite && q2.isFinite &&
      p1 >= 0 && p2 >= 0 && q1 >= 0 && q2 >= 0 && q1 + q2 > 0;
    final qty = valid ? q1 + q2 : 0.0;
    final investment = valid ? p1 * q1 + p2 * q2 : 0.0;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 15, 16, 110), children: [
      const Text('Average Calculator', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(19), child: Column(children: [
        field('Existing Buy Price (₹)', oldPrice), field('Existing Quantity', oldQty),
        field('New Buy Price (₹)', newPrice), field('New Quantity', newQty),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('NEW AVERAGE PRICE', style: TextStyle(fontWeight: FontWeight.w700,
          letterSpacing: 1, fontSize: 12)),
        const SizedBox(height: 10),
        FittedBox(fit: BoxFit.scaleDown, child: Text(valid ? rupees.format(investment / qty) : '₹0.00',
          style: const TextStyle(color: violet, fontSize: 35, fontWeight: FontWeight.w900))),
        const Divider(height: 30),
        ListTile(title: const Text('Total Quantity'),
          trailing: Text(qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2))),
        ListTile(title: const Text('Total Investment'), trailing: Text(rupees.format(investment))),
      ]))),
    ]);
  }
}
