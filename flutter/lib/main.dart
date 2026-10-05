import 'package:flutter/material.dart';

void main() {
  runApp(const FlutterCounterApp());
}

/// Flutter Counter: one app that reads, authenticates and writes on EVM,
/// Solana, Sui, Cosmos and NEAR testnets.
class FlutterCounterApp extends StatelessWidget {
  const FlutterCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Counter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      home: const Scaffold(body: Center(child: Text('Flutter Counter'))),
    );
  }
}
