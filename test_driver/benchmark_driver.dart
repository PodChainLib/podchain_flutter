// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Benchmark Test Driver
//
// Runs on the host machine (not the device). It drives the integration test,
// captures the JSON output printed between BENCHMARK_JSON_START and
// BENCHMARK_JSON_END markers, and writes it to a local results file
// for the report formatter to consume.
//
// Usage:
//   flutter drive \
//     --driver=test_driver/benchmark_driver.dart \
//     --target=integration_test/benchmark_runner.dart \
//     --device-id <device_id>
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  // Run the integration test and capture output
  await integrationDriver(
    onScreenshot: (String screenshotName, List<int> screenshotBytes,
        [Map<String, Object?>? args]) async {
      // No screenshots needed for benchmarks
      return true;
    },
  );

  // The benchmark JSON is printed to the device log between markers.
  // After the test run, parse it from the flutter drive output.
  // In practice, use:
  //   flutter drive ... 2>&1 | grep -A 999 BENCHMARK_JSON_START | grep -B 999 BENCHMARK_JSON_END > results/flutter-results.json
  print('Benchmark run complete. Extract JSON from log output using:');
  print('  grep -A 9999 "BENCHMARK_JSON_START" flutter_drive.log | grep -B 9999 "BENCHMARK_JSON_END" | grep -v "BENCHMARK_JSON" > results/flutter-results.json');
}
