# Parsanol Benchmark Suite

This directory contains comprehensive benchmarks that you can run yourself to verify performance claims.

## Quick Start

```bash
# Run all benchmarks (quick mode - skips large inputs)
bundle exec ruby benchmark/run_all.rb --quick

# Run all benchmarks including large inputs
bundle exec ruby benchmark/run_all.rb

# Run with verbose output
bundle exec ruby benchmark/run_all.rb --verbose

# Generate and view report
bundle exec ruby benchmark/run_all.rb --output reports
```

## What Gets Benchmarked

### Ruby Backends

| Backend | Description | How to Enable |
|---------|-------------|---------------|
| `parslet` | Original Parslet gem (pure Ruby) | `gem 'parslet'` |
| `parsanol-parslet` | Parsanol Parslet compatibility layer | `require 'parsanol/parslet'` |
| `parsanol-native` | Parsanol with Rust backend | `Parsanol::Native.parse()` |
| `regexp` | Pure regex tokenization (baseline) | N/A |

### Test Inputs

Located in `benchmark/inputs/`:

| Size | Description | Files |
|------|-------------|-------|
| tiny | Single value (~100 bytes) | `tiny/*.txt` |
| small | Simple object (~800 bytes) | `small/*.txt` |
| medium | Nested structure (~8KB) | `medium/*.txt` |
| large | Complex document (~80KB) | `large/*.txt` |

Input types:
- **json**: JSON objects with nested structures
- **expression**: Mathematical expressions
- **express**: EXPRESS schema language

## Running Benchmarks

### Full Benchmark Suite

```bash
cd parsanol-ruby
bundle install
bundle exec ruby benchmark/run_all.rb
```

This will:
1. Run benchmarks for all available backends
2. Run benchmarks for all input sizes (tiny, small, medium, large)
3. Print a summary with speedup factors
4. Save a JSON report to `benchmark/reports/`

### Quick Mode

```bash
# Skip large inputs for faster run
bundle exec ruby benchmark/run_all.rb --quick
```

### Options

```
-q, --quick          Skip large inputs for faster run
-p, --parser NAME    Test only this parser (parslet, parsanol-parslet, parsanol-native, regexp)
-v, --verbose        Show detailed output
-o, --output DIR     Output directory for reports
```

## Interpreting Results

### Sample Output

```
======================================================================
Parsanol Benchmark Suite - Evidence-Based Performance Verification
======================================================================

Benchmarking: json/medium
Input size: 8190 bytes
----------------------------------------------------------------------
  parslet              ...          9.3 iter/s  (±0.0%)
  parsanol-parslet     ...         10.1 iter/s  (±0.0%)
  parsanol-native      ...         44.4 iter/s  (±2.3%)
  regexp               ...       1544.4 iter/s  (±1.4%)

======================================================================
SPEEDUP FACTORS (vs parslet baseline)
======================================================================
json/medium: 4.8x faster with Rust backend
```

### What the Metrics Mean

- **iter/s**: Iterations per second (higher is better)
- **±X%**: Standard deviation (lower is more consistent)
- **Speedup**: How much faster parsanol-native is vs parslet

## Verification

To verify these benchmarks yourself:

```bash
# 1. Ensure native extension is built
bundle exec rake compile

# 2. Verify native extension is available
bundle exec ruby -e "puts Parsanol::Native.available?"
# => true

# 3. Run the benchmark
bundle exec ruby benchmark/run_all.rb --quick
```

## Benchmark Methodology

### Fairness

1. **Same Grammar**: All parsers use identical grammar rules
2. **Same Input**: All parsers parse the exact same input strings
3. **Warmup**: Each benchmark includes warmup iterations
4. **Statistical**: Results are averaged over multiple runs
5. **Isolation**: Each benchmark runs in isolation to prevent cache effects

### What We Measure

- **Parsing Time**: Time to parse input and return AST
- **Throughput**: Iterations per second

### What We Don't Measure

- Grammar compilation (done once, cached)
- Transform application (separate step)
- I/O operations

## Reproducibility

All benchmarks are:

1. **Deterministic**: Same input → same output
2. **Isolated**: No external dependencies
3. **Versioned**: Input files are committed to the repo
4. **Documented**: This README explains everything

## Contributing

To add a new benchmark:

1. Create parser in `benchmark/parsers/`
2. Add input files in `benchmark/inputs/{size}/`
3. Update `run_all.rb` to include it
4. Run and verify results
