import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

// ---------------------------------------------------------------------------
// ابزارهای کمکی: اعداد فارسی، جداکننده هزارگان، تاریخ شمسی
// ---------------------------------------------------------------------------

const _faDigits = '۰۱۲۳۴۵۶۷۸۹';
const _arDigits = '٠١٢٣٤٥٦٧٨٩';

String toPersianDigits(String input) {
  var out = input;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll('$i', _faDigits[i]);
  }
  return out;
}

String toEnglishDigits(String input) {
  var out = input;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(_faDigits[i], '$i').replaceAll(_arDigits[i], '$i');
  }
  return out;
}

String formatMoney(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return toPersianDigits(b.toString());
}

const _monthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

String formatJalali(Jalali j) =>
    toPersianDigits('${j.day} ${_monthNames[j.month - 1]} ${j.year}');

// ---------------------------------------------------------------------------
// مدل‌ها
// ---------------------------------------------------------------------------

class ExpenseCategory {
  final String name;
  final IconData icon;
  const ExpenseCategory(this.name, this.icon);
}

const categories = [
  ExpenseCategory('خوراک', Icons.restaurant),
  ExpenseCategory('حمل‌ونقل', Icons.directions_bus),
  ExpenseCategory('خرید', Icons.shopping_bag),
  ExpenseCategory('قبوض', Icons.receipt_long),
  ExpenseCategory('سلامت', Icons.local_hospital),
  ExpenseCategory('تفریح', Icons.movie),
  ExpenseCategory('سایر', Icons.more_horiz),
];

class Expense {
  final int id;
  final String title;
  final int amount; // به تومان
  final ExpenseCategory category;
  final Jalali date;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'category': category.name,
        'y': date.year,
        'm': date.month,
        'd': date.day,
      };

  factory Expense.fromJson(Map<String, dynamic> json) {
    final catName = json['category'] as String;
    final cat = categories.firstWhere(
      (c) => c.name == catName,
      orElse: () => categories.last,
    );
    return Expense(
      id: json['id'] as int,
      title: json['title'] as String,
      amount: json['amount'] as int,
      category: cat,
      date: Jalali(json['y'] as int, json['m'] as int, json['d'] as int),
    );
  }
}

// ---------------------------------------------------------------------------
// اپ
// ---------------------------------------------------------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'هزینه‌یاب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Expense> _expenses = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('expenses');
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => Expense.fromJson(e as Map<String, dynamic>))
            .toList();
        _expenses
          ..clear()
          ..addAll(list);
      }
    } catch (_) {
      // اگر داده خراب بود، با لیست خالی شروع می‌کنیم
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'expenses',
        jsonEncode(_expenses.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  int get _total => _expenses.fold(0, (sum, e) => sum + e.amount);

  int get _monthTotal {
    final now = Jalali.now();
    return _expenses
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .fold(0, (sum, e) => sum + e.amount);
  }

  Future<void> _addExpense() async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddExpenseSheet(),
    );
    if (result != null) {
      setState(() => _expenses.insert(0, result));
      _save();
    }
  }

  void _removeExpense(int index) {
    final removed = _expenses[index];
    setState(() => _expenses.removeAt(index));
    _save();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('هزینه حذف شد'),
          action: SnackBarAction(
            label: 'بازگرداندن',
            onPressed: () {
              setState(() => _expenses.insert(index, removed));
              _save();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('هزینه‌یاب')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.add),
        label: const Text('هزینه جدید'),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('هزینه‌های این ماه'),
                        const SizedBox(height: 4),
                        Text(
                          '${formatMoney(_monthTotal)} تومان',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('مجموع کل'),
                      const SizedBox(height: 4),
                      Text('${formatMoney(_total)} تومان'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _expenses.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 64),
                        SizedBox(height: 12),
                        Text('هنوز هزینه‌ای ثبت نکرده‌اید'),
                        SizedBox(height: 4),
                        Text('با دکمه «هزینه جدید» شروع کنید'),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: _expenses.length,
                    itemBuilder: (context, i) {
                      final e = _expenses[i];
                      return Dismissible(
                        key: ValueKey(e.id),
                        direction: DismissDirection.horizontal,
                        background: Container(
                          color: Colors.red.shade100,
                          alignment: AlignmentDirectional.centerStart,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete_outline),
                        ),
                        onDismissed: (_) => _removeExpense(i),
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(e.category.icon)),
                          title: Text(e.title),
                          subtitle: Text(
                            '${e.category.name} • ${formatJalali(e.date)}',
                          ),
                          trailing: Text(
                            '${formatMoney(e.amount)} تومان',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// فرم افزودن هزینه
// ---------------------------------------------------------------------------

class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({super.key});

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  int _selected = 0;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final raw = toEnglishDigits(_amountCtrl.text)
        .replaceAll(RegExp(r'[,٬،\s]'), '');
    final amount = int.tryParse(raw);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'مبلغ را درست وارد کنید');
      return;
    }
    final cat = categories[_selected];
    final title = _titleCtrl.text.trim();
    Navigator.pop(
      context,
      Expense(
        id: DateTime.now().microsecondsSinceEpoch,
        title: title.isEmpty ? cat.name : title,
        amount: amount,
        category: cat,
        date: Jalali.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ثبت هزینه جدید',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'مبلغ (تومان)',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'عنوان (اختیاری)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < categories.length; i++)
                  ChoiceChip(
                    avatar: Icon(categories[i].icon, size: 18),
                    label: Text(categories[i].name),
                    selected: i == _selected,
                    onSelected: (_) => setState(() => _selected = i),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('ثبت هزینه')),
          ],
        ),
      ),
    );
  }
}
