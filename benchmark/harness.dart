// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Flutter — Benchmark Harness
//
// Provides the timing harness for all mobile-side benchmarks.
// Mirrors the structure of the server-side runner.ts for consistency.
//
// On Flutter, benchmarks run inside flutter_test using the integration_test
// package so they execute on a real device rather than the Dart VM —
// this is critical because key generation and signing latency on the
// Android Keystore path differs significantly from the host VM.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';

/// Holds the result of a single benchmark operation.
class BenchmarkResult {
  final String name;
  final int iterations;
  final double minMs;
  final double maxMs;
  final double meanMs;
  final double medianMs;
  final double p95Ms;
  final double p99Ms;

  const BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.minMs,
    required this.maxMs,
    required this.meanMs,
    required this.medianMs,
    required this.p95Ms,
    required this.p99Ms,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'iterations': iterations,
        'min_ms': minMs,
        'max_ms': maxMs,
        'mean_ms': meanMs,
        'median_ms': medianMs,
        'p95_ms': p95Ms,
        'p99_ms': p99Ms,
      };

  @override
  String toString() =>
      '${name.padRight(48)} median: ${medianMs.toStringAsFixed(2)}ms'
      '  mean: ${meanMs.toStringAsFixed(2)}ms'
      '  min: ${minMs.toStringAsFixed(2)}ms'
      '  max: ${maxMs.toStringAsFixed(2)}ms'
      '  p95: ${p95Ms.toStringAsFixed(2)}ms';
}

/// Runs a single async operation [iterations] times (with [warmup] warmup runs)
/// and returns a [BenchmarkResult] with statistical summary.
Future<BenchmarkResult> runBenchmark(
  String name,
  Future<void> Function() fn, {
  int iterations = 50,
  int warmup = 5,
}) async {
  // Warmup — allow platform lazy initialisation to settle
  for (int i = 0; i < warmup; i++) {
    await fn();
  }

  final samples = <double>[];

  for (int i = 0; i < iterations; i++) {
    final start = DateTime.now().microsecondsSinceEpoch;
    await fn();
    final end = DateTime.now().microsecondsSinceEpoch;
    samples.add((end - start) / 1000.0); // microseconds → milliseconds
  }

  samples.sort();

  final min    = samples.first;
  final max    = samples.last;
  final mean   = samples.reduce((a, b) => a + b) / samples.length;
  final median = _percentile(samples, 50);
  final p95    = _percentile(samples, 95);
  final p99    = _percentile(samples, 99);

  final result = BenchmarkResult(
    name: name,
    iterations: iterations,
    minMs: _round(min),
    maxMs: _round(max),
    meanMs: _round(mean),
    medianMs: _round(median),
    p95Ms: _round(p95),
    p99Ms: _round(p99),
  );

  // Log to Flutter DevTools timeline for visual inspection
  log(result.toString(), name: 'PODCHAIN.Benchmark');

  return result;
}

double _percentile(List<double> sorted, int p) {
  final index = (p / 100) * (sorted.length - 1);
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = index - lower;
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
}

double _round(double n) => (n * 100).round() / 100;

/// Prints a formatted summary table for all results in a suite.
void printSuiteResults(String suiteName, List<BenchmarkResult> results) {
  final divider = '═' * 80;
  print('\n$divider');
  print(' PODCHAIN FLUTTER BENCHMARKS: $suiteName');
  print(divider);
  print(
    '${'Operation'.padRight(48)}'
    '${'Median'.padLeft(10)}'
    '${'Mean'.padLeft(10)}'
    '${'Min'.padLeft(10)}'
    '${'Max'.padLeft(10)}',
  );
  print('─' * 80);
  for (final r in results) {
    print(
      '${r.name.padRight(48)}'
      '${_fmt(r.medianMs)}'
      '${_fmt(r.meanMs)}'
      '${_fmt(r.minMs)}'
      '${_fmt(r.maxMs)}',
    );
  }
  print(divider);
}

String _fmt(double ms) => '${ms.toStringAsFixed(2)}ms'.padLeft(10);
