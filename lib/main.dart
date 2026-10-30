import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'هزینه‌یاب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final j = Jalali.now();
    return Scaffold(
      appBar: AppBar(title: const Text('هزینه‌یاب')),
      body: Center(
        child: Text(
          'امروز: ${j.year}/${j.month}/${j.day}',
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
