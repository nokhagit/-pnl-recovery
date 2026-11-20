import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PnlApp());
}

const green = Color(0xFF16834A);
const red = Color(0xFFC34336);
const blue = Color(0xFF3855C8);

final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final dayFormat = DateFormat('dd MMM yyyy');

String rupees(int paise) => money.format(paise / 100);

class Entry {
  final String id;
  final int amountPaise; // Positive = profit, negative = loss.
  final DateTime date;
  final String note;

  const Entry({required this.id, required this.amountPaise, required this.date, required this.note});

  Map<String, dynamic> toJson() => {
    'id': id,
    'amountPaise': amountPaise,
    'date': date.toIso8601String(),
    'note': note,
  };

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    id: json['id'] as String,
    amountPaise: (json['amountPaise'] as num).toInt(),
    date: DateTime.parse(json['date'] as String),
    note: (json['note'] as String?) ?? '',
  );
}

class PnlApp extends StatelessWidget {
  const PnlApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'P&L Recovery',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.light),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF6F7F9)),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
    home: const Dashboard(),
  );
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  static const storageKey = 'pnl_entries_v1';
  List<Entry> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      final loaded = raw == null
          ? <Entry>[]
          : (jsonDecode(raw) as List)
              .map((item) => Entry.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
      if (mounted) setState(() { entries = loaded; loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load saved data. Existing data was not changed.'),
        ));
      }
    }
  }

  Future<bool> _persist(List<Entry> next) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(storageKey, jsonEncode(next.map((e) => e.toJson()).toList()));
      if (!ok) throw Exception('Save failed');
      if (mounted) setState(() => entries = next);
      return true;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save. Please try again.')),
      );
      return false;
    }
  }

  Future<void> _edit([Entry? existing]) async {
    final result = await showModalBottomSheet<Entry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => EntrySheet(existing: existing),
    );
    if (result == null || !mounted) return;
    final next = [...entries];
    final index = next.indexWhere((e) => e.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    await _persist(next);
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(action, style: const TextStyle(color: red))),
          ],
        ),
      ) ?? false;

  Future<void> _delete(Entry entry) async {
    if (await _confirm('Delete entry?', 'This entry will be removed from your P&L.', 'Delete')) {
      await _persist(entries.where((e) => e.id != entry.id).toList());
    }
  }

  Future<void> _reset() async {
    if (!await _confirm('Reset all data?', 'This will delete every saved entry.', 'Continue')) return;
    if (!mounted) return;
    if (!await _confirm('Final confirmation', 'This cannot be undone. Permanently delete all entries?', 'Delete all')) return;
    await _persist([]);
  }

  @override
  Widget build(BuildContext context) {
    final profit = entries.where((e) => e.amountPaise > 0).fold<int>(0, (s, e) => s + e.amountPaise);
    final loss = entries.where((e) => e.amountPaise < 0).fold<int>(0, (s, e) => s - e.amountPaise);
    final net = profit - loss;
    final recovered = net >= 0;
    final sorted = [...entries]..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('P&L Recovery', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) { if (value == 'reset') _reset(); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset All Data'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: loading ? null : () => _edit(),
        backgroundColor: blue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: recovered ? const Color(0xFFE7F7ED) : const Color(0xFFFFEEE9),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(recovered ? 'Net Profit' : 'Loss to Recover',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: recovered ? green : red)),
                    const SizedBox(height: 10),
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                      child: Text(rupees(recovered ? net : -net),
                        style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: recovered ? green : red))),
                    const SizedBox(height: 8),
                    Text(recovered ? '✓ All Loss Recovered!' : 'Profit needed to reach break-even',
                      style: TextStyle(color: recovered ? green : red)),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _summary('Total Profit', profit, green, Icons.trending_up)),
                  const SizedBox(width: 12),
                  Expanded(child: _summary('Total Loss', loss, red, Icons.trending_down)),
                ]),
                const SizedBox(height: 26),
                const Text('Recent Entries', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (sorted.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 56),
                    child: Center(child: Text('No entries yet. Tap + to add your first trade.'))),
                ...sorted.map((entry) => Card(
                  color: Colors.white,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _edit(entry),
                    leading: CircleAvatar(
                      backgroundColor: entry.amountPaise >= 0 ? const Color(0xFFE7F7ED) : const Color(0xFFFFEEE9),
                      child: Icon(entry.amountPaise >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        color: entry.amountPaise >= 0 ? green : red),
                    ),
                    title: Text(entry.note.isEmpty ? (entry.amountPaise >= 0 ? 'Profit' : 'Loss') : entry.note,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(dayFormat.format(entry.date)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${entry.amountPaise >= 0 ? '+' : '−'}${rupees(entry.amountPaise.abs())}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: entry.amountPaise >= 0 ? green : red)),
                      PopupMenuButton<String>(
                        onSelected: (value) => value == 'edit' ? _edit(entry) : _delete(entry),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ]),
                  ),
                )),
              ],
            ),
    );
  }

  Widget _summary(String title, int value, Color color, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 5),
        Flexible(child: Text(title, style: const TextStyle(fontSize: 12)))]),
      const SizedBox(height: 10),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Text(rupees(value), style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: color))),
    ]),
  );
}

class EntrySheet extends StatefulWidget {
  final Entry? existing;
  const EntrySheet({super.key, this.existing});

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController noteController;
  late bool isProfit;
  late DateTime date;

  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    isProfit = (old?.amountPaise ?? 1) > 0;
    date = old?.date ?? DateTime.now();
    amountController = TextEditingController(text: old == null ? '' : (old.amountPaise.abs() / 100).toStringAsFixed(2));
    noteController = TextEditingController(text: old?.note ?? '');
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  int? _parsePaise(String input) {
    final value = input.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final fractional = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
    final paise = whole * 100 + fractional;
    return paise > 0 && paise <= 100000000000000 ? paise : null;
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final paise = _parsePaise(amountController.text)!;
    Navigator.pop(context, Entry(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      amountPaise: isProfit ? paise : -paise,
      date: DateTime(date.year, date.month, date.day),
      note: noteController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
    child: SingleChildScrollView(
      child: Form(key: formKey, child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'Add Entry' : 'Edit Entry',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _typeButton('Profit', true, green)),
            const SizedBox(width: 12),
            Expanded(child: _typeButton('Loss', false, red)),
          ]),
          const SizedBox(height: 18),
          TextFormField(
            controller: amountController,
            autofocus: widget.existing == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹ '),
            validator: (value) => _parsePaise(value ?? '') == null ? 'Enter a valid amount (up to 2 decimals)' : null,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(dayFormat.format(date)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => date = picked);
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: noteController,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Nifty Option, Intraday, Swing'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save,
            style: FilledButton.styleFrom(backgroundColor: blue, padding: const EdgeInsets.all(16)),
            child: const Text('Save Entry')),
        ],
      )),
    ),
  );

  Widget _typeButton(String title, bool value, Color color) => OutlinedButton(
    onPressed: () => setState(() => isProfit = value),
    style: OutlinedButton.styleFrom(
      backgroundColor: isProfit == value ? color.withValues(alpha: 0.1) : Colors.white,
      side: BorderSide(color: isProfit == value ? color : Colors.grey.shade300, width: 1.5),
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
    child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
  );
}
