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
  final s = n.abs().toString();
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

const expenseCategories = [
  ExpenseCategory('خوراک', Icons.restaurant),
  ExpenseCategory('حمل‌ونقل', Icons.directions_bus),
  ExpenseCategory('خرید', Icons.shopping_bag),
  ExpenseCategory('قبوض', Icons.receipt_long),
  ExpenseCategory('سلامت', Icons.local_hospital),
  ExpenseCategory('تفریح', Icons.movie),
  ExpenseCategory('سایر', Icons.more_horiz),
];

const incomeCategories = [
  ExpenseCategory('حقوق', Icons.payments),
  ExpenseCategory('کسب‌وکار', Icons.storefront),
  ExpenseCategory('هدیه', Icons.card_giftcard),
  ExpenseCategory('سایر', Icons.more_horiz),
];

ExpenseCategory findCategory(String name, bool isIncome) {
  final list = isIncome ? incomeCategories : expenseCategories;
  return list.firstWhere((c) => c.name == name, orElse: () => list.last);
}

class Expense {
  final int id;
  final String title;
  final int amount; // به تومان
  final ExpenseCategory category;
  final Jalali date;
  final bool isIncome;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.isIncome = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'category': category.name,
        'income': isIncome,
        'y': date.year,
        'm': date.month,
        'd': date.day,
      };

  factory Expense.fromJson(Map<String, dynamic> json) {
    final income = (json['income'] as bool?) ?? false;
    return Expense(
      id: json['id'] as int,
      title: json['title'] as String,
      amount: json['amount'] as int,
      category: findCategory(json['category'] as String, income),
      date: Jalali(json['y'] as int, json['m'] as int, json['d'] as int),
      isIncome: income,
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
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = Jalali.now();
    _year = now.year;
    _month = now.month;
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

  // ---- ماه انتخاب‌شده ----

  bool get _canGoNext {
    final now = Jalali.now();
    return _year < now.year || (_year == now.year && _month < now.month);
  }

  void _shiftMonth(int delta) {
    var m = _month + delta;
    var y = _year;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    setState(() {
      _year = y;
      _month = m;
    });
  }

  List<Expense> get _monthItems {
    final list = _expenses
        .where((e) => e.date.year == _year && e.date.month == _month)
        .toList();
    list.sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  // ---- افزودن / ویرایش / حذف ----

  Future<void> _addExpense() async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddExpenseSheet(),
    );
    if (result != null) {
      setState(() {
        _expenses.insert(0, result);
        // نمایش ماهی که تراکنش در آن ثبت شده
        _year = result.date.year;
        _month = result.date.month;
      });
      _save();
    }
  }

  Future<void> _editExpense(Expense old) async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddExpenseSheet(initial: old),
    );
    if (result != null) {
      final idx = _expenses.indexWhere((e) => e.id == old.id);
      if (idx >= 0) {
        setState(() => _expenses[idx] = result);
        _save();
      }
    }
  }

  void _removeExpense(Expense e) {
    final idx = _expenses.indexWhere((x) => x.id == e.id);
    if (idx < 0) return;
    setState(() => _expenses.removeAt(idx));
    _save();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('حذف شد'),
          action: SnackBarAction(
            label: 'بازگرداندن',
            onPressed: () {
              setState(() => _expenses.insert(idx, e));
              _save();
            },
          ),
        ),
      );
  }

  // ---- ساخت صفحه ----

  Widget _stat(String label, int value, Color? color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            formatMoney(value),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Text('تومان', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _monthItems;
    final income =
        items.where((e) => e.isIncome).fold(0, (sum, e) => sum + e.amount);
    final expense =
        items.where((e) => !e.isIncome).fold(0, (sum, e) => sum + e.amount);
    final balance = income - expense;

    return Scaffold(
      appBar: AppBar(title: const Text('هزینه‌یاب')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.add),
        label: const Text('ثبت جدید'),
      ),
      body: Column(
        children: [
          // انتخاب ماه
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'ماه قبل',
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    '${_monthNames[_month - 1]} ${toPersianDigits('$_year')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'ماه بعد',
                  onPressed: _canGoNext ? () => _shiftMonth(1) : null,
                ),
              ],
            ),
          ),
          // خلاصه ماه
          Card(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
                children: [
                  _stat('درآمد', income, Colors.green.shade800),
                  _stat('هزینه', expense, Colors.red.shade700),
                  _stat(
                    balance < 0 ? 'کسری' : 'مانده',
                    balance,
                    balance < 0 ? Colors.red.shade700 : null,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 64,
                            ),
                            SizedBox(height: 12),
                            Text('در این ماه چیزی ثبت نشده'),
                            SizedBox(height: 4),
                            Text('با دکمه «ثبت جدید» شروع کنید'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          final color = e.isIncome
                              ? Colors.green.shade800
                              : Colors.red.shade700;
                          return Dismissible(
                            key: ValueKey(e.id),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              color: Colors.red.shade100,
                              alignment: AlignmentDirectional.centerStart,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: const Icon(Icons.delete_outline),
                            ),
                            onDismissed: (_) => _removeExpense(e),
                            child: ListTile(
                              onTap: () => _editExpense(e),
                              leading: CircleAvatar(
                                backgroundColor: e.isIncome
                                    ? Colors.green.shade100
                                    : Colors.red.shade50,
                                child: Icon(e.category.icon, color: color),
                              ),
                              title: Text(e.title),
                              subtitle: Text(
                                '${e.category.name} • ${formatJalali(e.date)}',
                              ),
                              trailing: Text(
                                '${formatMoney(e.amount)} تومان',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
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
// فرم افزودن / ویرایش
// ---------------------------------------------------------------------------

class AddExpenseSheet extends StatefulWidget {
  final Expense? initial;
  const AddExpenseSheet({super.key, this.initial});

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _amountCtrl;
  late bool _isIncome;
  late int _selected;
  String? _error;

  List<ExpenseCategory> get _cats =>
      _isIncome ? incomeCategories : expenseCategories;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _isIncome = init?.isIncome ?? false;
    _titleCtrl = TextEditingController(text: init?.title ?? '');
    _amountCtrl = TextEditingController(
      text: init == null ? '' : toPersianDigits(init.amount.toString()),
    );
    var idx = 0;
    if (init != null) {
      idx = _cats.indexWhere((c) => c.name == init.category.name);
      if (idx < 0) idx = 0;
    }
    _selected = idx;
  }

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
    final cat = _cats[_selected];
    final title = _titleCtrl.text.trim();
    final init = widget.initial;
    Navigator.pop(
      context,
      Expense(
        id: init?.id ?? DateTime.now().microsecondsSinceEpoch,
        title: title.isEmpty ? cat.name : title,
        amount: amount,
        category: cat,
        date: init?.date ?? Jalali.now(),
        isIncome: _isIncome,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final cats = _cats;
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
            Text(
              editing ? 'ویرایش' : 'ثبت جدید',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('هزینه'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('درآمد'),
                  icon: Icon(Icons.arrow_downward),
                ),
              ],
              selected: {_isIncome},
              onSelectionChanged: (s) => setState(() {
                _isIncome = s.first;
                _selected = 0;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              autofocus: !editing,
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
                for (var i = 0; i < cats.length; i++)
                  ChoiceChip(
                    avatar: Icon(cats[i].icon, size: 18),
                    label: Text(cats[i].name),
                    selected: i == _selected,
                    onSelected: (_) => setState(() => _selected = i),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(editing ? 'ذخیره تغییرات' : 'ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}
