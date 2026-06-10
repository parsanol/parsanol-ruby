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

# Run only the cache threshold comparison
bundle exec ruby benchmark/run_all.rb --type cache_threshold --quick --no-diagram

# Generate and view report
bundle exec ruby benchmark/run_all.rb --output reports
```

## What Gets Benchmarked

### Ruby Backends

| Backend | Description | How to Enable |
|---------|-------------|---------------|
| `parslet-ruby` | Original Parslet gem (pure Ruby baseline) | `gem 'parslet'` |
| `parsanol-ruby` | Parsanol Ruby parser backend | `require 'parsanol'` |
| `parsanol-native` | Parsanol with Rust backend | `rake compile` (builds the native extension) |
| `parsanol-cache-default` | Cache-threshold benchmark using parser defaults | `--type cache_threshold` |
| `parsanol-cache-1000` | Cache-threshold benchmark using conservative caching | `--type cache_threshold` |

The runner probes the backends at startup and skips unavailable ones; run
with `--verbose` to see the probe results. The cache-threshold backends are
opt-in (selected via `--type cache_threshold` or `--parser parsanol-cache-*`)
and are not probed otherwise.

### Test Inputs

Located in `benchmark/inputs/`:

| Size | JSON input | Files |
|------|------------|-------|
| tiny | Single value (76 bytes) | `tiny/*.txt` |
| small | Simple object (~800 bytes) | `small/*.txt` |
| medium | Nested structure (~8KB) | `medium/*.txt` |
| large | Complex document (~86KB) | `large/*.txt` |

Byte counts above are for the JSON inputs; the other input types have their
own sizes per tier (e.g. `tiny/expression.txt` is 11 bytes,
`tiny/express.txt` is 140 bytes, `large/express.txt` is ~16KB).

Input types:
- **json**: JSON objects with nested structures
- **expression**: Mathematical expressions
- **express**: EXPRESS schema language
- **cache_threshold**: Recursive parser-class grammar for comparing default and conservative cache thresholds

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
-p, --parser NAME    Test only this parser (see backend names above)
-t, --type TYPE      Test only this input type
-v, --verbose        Show detailed output
-o, --output DIR     Output directory for reports
    --no-diagram     Hide the introductory approaches/cache-threshold overview
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
  parslet-ruby         ...          9.3 iter/s  (±0.0%)
  parsanol-ruby        ...         10.1 iter/s  (±0.0%)
  parsanol-native      ...         44.4 iter/s  (±2.3%)

======================================================================
SPEEDUP FACTORS (vs parslet-ruby baseline)
======================================================================
json/medium: parsanol-native is 4.8x faster
```

### What the Metrics Mean

- **iter/s**: Iterations per second (higher is better)
- **±X%**: Standard deviation (lower is more consistent)
- **Speedup**: How much faster each backend is vs the `parslet-ruby` baseline

## Verification

To verify these benchmarks yourself:

```bash
# 1. Ensure native extension is built
bundle exec rake compile

# 2. Verify native extension is available
bundle exec ruby -e "require 'parsanol'; puts Parsanol::Native.available?"
# => true

# 3. Run the benchmark
bundle exec ruby benchmark/run_all.rb --quick
```

## Benchmark Methodology

### Fairness

1. **Same Grammar**: All parsers use identical grammar rules
2. **Same Input**: All parsers parse the exact same input strings
3. **Warmup**: Each benchmark includes warmup iterations
4. **Statistical**: Results are averaged over multiple runs (benchmark-ips)
5. **Fresh parser per backend**: Each backend is measured with its own parser
   instance, sequentially in one process

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

## Other Benchmark Scripts

### benchmark_suite.rb (`rake benchmark:all`)

`benchmark/benchmark_suite.rb` is a second, single-combination runner (one
input type and size per invocation) with backends `run_all.rb` does not have —
most notably the **Parslet compatibility layer** (`parsanol-parslet`, via
`require "parsanol/parslet"`) for measuring compat-layer overhead, and a
**regexp tokenization baseline** as a ceiling reference (it only tokenizes, it
is not a real parser).

```bash
bundle exec rake benchmark:all                                          # json/medium, all available backends
bundle exec ruby benchmark/benchmark_suite.rb --parser parsanol-parslet # one backend
bundle exec ruby benchmark/benchmark_suite.rb --type express --size small
```

Backend/type support (combinations without a checked-in parser file are
skipped with a warning):

| Backend | json | expression | express |
|---------|------|------------|---------|
| `parslet` | ✅ | file not checked in | file not checked in |
| `parsanol-ruby` | ✅ | file not checked in | ✅ |
| `parsanol-native` | ✅ | file not checked in | ✅ |
| `parsanol-parslet` | ✅ | file not checked in | file not checked in |
| `racc` | file not checked in | file not checked in | not supported |
| `regexp` | ✅ | ✅ | ✅ |

### Tasks referencing scripts that are not checked in

`rake benchmark:examples`, `rake benchmark:export`, `rake benchmark:quick`
(and the bare `rake benchmark`, an alias for `benchmark:quick`) point at
`benchmark/example_benchmarks.rb` and `benchmark/benchmark_runner.rb`, which
are not in the repository. `rake benchmark:all` is the only benchmark rake
task wired to a checked-in script.

## Contributing

To add a new benchmark:

1. Create parser in `benchmark/parsers/`
2. Add input files in `benchmark/inputs/{size}/`
3. Update `run_all.rb` (and/or `PARSER_FILES` in `benchmark_suite.rb`) to include it
4. Run and verify results
