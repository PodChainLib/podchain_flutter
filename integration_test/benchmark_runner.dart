// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Integration Test Entry Point
//
// Required by the integration_test package. This file is the entry point
// that the test runner loads onto the device. It calls
// integrationDriver in the test driver and runs all benchmark tests.
//
// Run on a physical device:
//   flutter test integration_test/benchmark_runner.dart \
//     --device-id <your_device_id>
//
// To list connected devices: flutter devices
// ─────────────────────────────────────────────────────────────────────────────

import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';

// Import all benchmark suites
import '../benchmark/podchain_benchmark_test.dart' as mobile_benchmarks;
import '../benchmark/vectors_test.dart' as vector_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Minimal app shell required for integration_test to render
  runApp(const MaterialApp(home: Scaffold(body: Center(
    child: Text('PODCHAIN Benchmark Suite\nRunning…',
      textAlign: TextAlign.center),
  ))));

  // Execute suites in order
  // 1. Cross-platform serialisation vectors (must pass before benchmarks run)
  vector_tests.main();

  // 2. Mobile performance benchmarks
  mobile_benchmarks.main();
}
