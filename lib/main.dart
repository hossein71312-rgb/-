import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
// تشخیص پیامک بانکی
// ---------------------------------------------------------------------------

String _normalizeSms(String t) {
  return toEnglishDigits(t)
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('٬', ',');
}

Jalali? _safeJalali(int y, int m, int d) {
  if (y < 1300 || y > 1500 || m < 1 || m > 12 || d < 1) return null;
  final maxDay = m <= 6 ? 31 : (m <= 11 ? 30 : 29);
  if (d > maxDay) return null;
  return Jalali(y, m, d);
}

// پیامک‌هایی که سال ندارند: اگر تاریخ از امروز جلوتر باشد، مال سال قبل است
int _inferYear(int month, int day) {
  final now = Jalali.now();
  if (month > now.month || (month == now.month && day > now.day)) {
    return now.year - 1;
  }
  return now.year;
}

const _bankNames = [
  'گردشگری',
  'ملی',
  'ملت',
  'پارسیان',
  'صادرات',
  'سپه',
  'تجارت',
  'رفاه',
  'پاسارگاد',
  'سامان',
  'کشاورزی',
  'مسکن',
  'شهر',
  'آینده',
  'اقتصاد نوین',
  'سینا',
  'سرمایه',
  'قوامین',
  'ایران زمین',
  'دی',
];

String _smsTitle(String t, bool isIncome) {
  final base = isIncome
      ? 'واریز به حساب'
      : (t.contains('خرید') ? 'خرید با کارت' : 'برداشت از حساب');
  for (final b in _bankNames) {
    if (t.contains('بانک $b')) return '$base (بانک $b)';
  }
  return base;
}

/// متن پیامک بانکی را می‌خواند و یک تراکنش پیشنهادی برمی‌گرداند.
/// اگر مبلغی پیدا نشود null برمی‌گرداند.
Expense? parseBankSms(String raw) {
  final t = _normalizeSms(raw);

  // ---- مبلغ ----
  RegExpMatch? m =
      RegExp(r'مبلغ\s*:?\s*(\d[\d,]*)\s*([+\-])?').firstMatch(t);
  m ??= RegExp(r'(?:برداشت|واریز|پرداخت|خرید)\s*:\s*(\d[\d,]*)\s*([+\-])?')
      .firstMatch(t);
  if (m == null) return null;

  final value = int.tryParse(m.group(1)!.replaceAll(',', ''));
  if (value == null) return null;
  // مبلغ پیامک‌ها معمولاً ریال است
  final amount = t.contains('تومان') ? value : value ~/ 10;
  if (amount <= 0) return null;

  // ---- جهت تراکنش ----
  final sign = m.group(2);
  final bool isIncome;
  if (sign == '+') {
    isIncome = true;
  } else if (sign == '-') {
    isIncome = false;
  } else if (t.contains('برداشت')) {
    isIncome = false;
  } else if (t.contains('واریز')) {
    isIncome = true;
  } else {
    isIncome = false;
  }

  // ---- تاریخ ----
  Jalali? date;
  final full = RegExp(r'(\d{4})/(\d{1,2})/(\d{1,2})').firstMatch(t);
  if (full != null) {
    date = _safeJalali(
      int.parse(full.group(1)!),
      int.parse(full.group(2)!),
      int.parse(full.group(3)!),
    );
  } else {
    final short3 = RegExp(r'(\d{2})/(\d{1,2})/(\d{1,2})').firstMatch(t);
    if (short3 != null) {
      date = _safeJalali(
        1400 + int.parse(short3.group(1)!),
        int.parse(short3.group(2)!),
        int.parse(short3.group(3)!),
      );
    } else {
      final md = RegExp(r'(\d{1,2})/(\d{1,2})').firstMatch(t);
      final packed = RegExp(r'(?:^|\s)(\d{2})(\d{2})\s*-\s*\d{1,2}:\d{2}')
          .firstMatch(t);
      final hit = md ?? packed;
      if (hit != null) {
        final mo = int.parse(hit.group(1)!);
        final da = int.parse(hit.group(2)!);
        date = _safeJalali(_inferYear(mo, da), mo, da);
      }
    }
  }
  date ??= Jalali.now();

  return Expense(
    id: DateTime.now().microsecondsSinceEpoch,
    title: _smsTitle(t, isIncome),
    amount: amount,
    category: findCategory('سایر', isIncome),
    date: date,
    isIncome: isIncome,
  );
}

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
  int _tab = 0;

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

  Future<void> _importSms() async {
    final parsed = await showDialog<Expense>(
      context: context,
      builder: (_) => const SmsPasteDialog(),
    );
    if (parsed != null && mounted) {
      await _addExpense(prefill: parsed);
    }
  }

  Future<void> _addExpense({Expense? prefill}) async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddExpenseSheet(initial: prefill, isNew: prefill != null),
    );
    if (result != null) {
      setState(() {
        _tab = 0;
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

  int _sum(int y, int m, bool income) {
    return _expenses
        .where((e) =>
            e.isIncome == income && e.date.year == y && e.date.month == m)
        .fold(0, (sum, e) => sum + e.amount);
  }

  List<List<int>> _lastMonths(int count) {
    final out = <List<int>>[];
    var y = _year;
    var m = _month;
    for (var i = 0; i < count; i++) {
      out.insert(0, [y, m]);
      m--;
      if (m < 1) {
        m = 12;
        y--;
      }
    }
    return out;
  }

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

  Widget _monthSelector() {
    return Padding(
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'ماه بعد',
            onPressed: _canGoNext ? () => _shiftMonth(1) : null,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(int income, int expense, int balance) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
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
    );
  }

  Widget _transactionsList(List<Expense> items) {
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 64),
            SizedBox(height: 12),
            Text('در این ماه چیزی ثبت نشده'),
            SizedBox(height: 4),
            Text('با دکمه «ثبت جدید» شروع کنید'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        final color = e.isIncome ? Colors.green.shade800 : Colors.red.shade700;
        return Dismissible(
          key: ValueKey(e.id),
          direction: DismissDirection.horizontal,
          background: Container(
            color: Colors.red.shade100,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) => _removeExpense(e),
          child: ListTile(
            onTap: () => _editExpense(e),
            leading: CircleAvatar(
              backgroundColor:
                  e.isIncome ? Colors.green.shade100 : Colors.red.shade50,
              child: Icon(e.category.icon, color: color),
            ),
            title: Text(e.title),
            subtitle: Text('${e.category.name} • ${formatJalali(e.date)}'),
            trailing: Text(
              '${formatMoney(e.amount)} تومان',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        );
      },
    );
  }

  // ---- گزارش ----

  Widget _catRow(String name, int amount, int total) {
    final cat = findCategory(name, false);
    final frac = total == 0 ? 0.0 : amount / total;
    final percent = (frac * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Icon(cat.icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(name)),
              Text(
                '${formatMoney(amount)} تومان',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                child: Text(
                  toPersianDigits('${percent}٪'),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: frac, minHeight: 8),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _bar(Color color, double height) {
    return Container(
      width: 10,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    );
  }

  Widget _trendChart() {
    final months = _lastMonths(6);
    final incomes = months.map((ym) => _sum(ym[0], ym[1], true)).toList();
    final expenses = months.map((ym) => _sum(ym[0], ym[1], false)).toList();
    var maxV = 0;
    for (final v in [...incomes, ...expenses]) {
      if (v > maxV) maxV = v;
    }
    if (maxV == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('هنوز داده‌ای برای نمودار نیست')),
      );
    }
    const chartHeight = 110.0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(Colors.green.shade600, 'درآمد'),
            const SizedBox(width: 16),
            _legendDot(Colors.red.shade400, 'هزینه'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < months.length; i++)
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: chartHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bar(Colors.green.shade600,
                              incomes[i] / maxV * chartHeight),
                          const SizedBox(width: 3),
                          _bar(Colors.red.shade400,
                              expenses[i] / maxV * chartHeight),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _monthNames[months[i][1] - 1],
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _reportView(List<Expense> items) {
    final expenseItems = items.where((e) => !e.isIncome).toList();
    final total = expenseItems.fold(0, (sum, e) => sum + e.amount);
    final byCat = <String, int>{};
    for (final e in expenseItems) {
      byCat[e.category.name] = (byCat[e.category.name] ?? 0) + e.amount;
    }
    final rows = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'هزینه‌ها بر اساس دسته',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('در این ماه هزینه‌ای ثبت نشده')),
          ),
        for (final r in rows) _catRow(r.key, r.value, total),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'روند ۶ ماه اخیر',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _trendChart(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _monthItems;
    final income =
        items.where((e) => e.isIncome).fold(0, (sum, e) => sum + e.amount);
    final expense =
        items.where((e) => !e.isIncome).fold(0, (sum, e) => sum + e.amount);
    final balance = income - expense;

    Widget content;
    if (!_loaded) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_tab == 0) {
      content = Column(
        children: [
          _summaryCard(income, expense, balance),
          Expanded(child: _transactionsList(items)),
        ],
      );
    } else {
      content = _reportView(items);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('هزینه‌یاب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sms_outlined),
            tooltip: 'ثبت از پیامک بانکی',
            onPressed: _importSms,
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _addExpense(),
              icon: const Icon(Icons.add),
              label: const Text('ثبت جدید'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            label: 'تراکنش‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            label: 'گزارش',
          ),
        ],
      ),
      body: Column(
        children: [
          _monthSelector(),
          Expanded(child: content),
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
  final bool isNew; // true یعنی مقدار اولیه از پیامک آمده و هنوز ثبت نشده
  const AddExpenseSheet({super.key, this.initial, this.isNew = false});

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
        id: (init != null && !widget.isNew)
            ? init.id
            : DateTime.now().microsecondsSinceEpoch,
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
    final editing = widget.initial != null && !widget.isNew;
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
            if (widget.initial != null) ...[
              Text(
                'تاریخ: ${formatJalali(widget.initial!.date)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
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

// ---------------------------------------------------------------------------
// پنجره چسباندن پیامک بانکی
// ---------------------------------------------------------------------------

class SmsPasteDialog extends StatefulWidget {
  const SmsPasteDialog({super.key});

  @override
  State<SmsPasteDialog> createState() => _SmsPasteDialogState();
}

class _SmsPasteDialogState extends State<SmsPasteDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      setState(() {
        _ctrl.text = text;
        _error = null;
      });
    }
  }

  void _parse() {
    final result = parseBankSms(_ctrl.text);
    if (result == null) {
      setState(() => _error = 'مبلغ در متن پیدا نشد. کل متن پیامک را کپی کنید.');
      return;
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ثبت از پیامک بانکی'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            minLines: 4,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'متن پیامک بانکی را اینجا بچسبانید',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('چسباندن از کلیپ‌بورد'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(onPressed: _parse, child: const Text('تشخیص')),
      ],
    );
  }
}
