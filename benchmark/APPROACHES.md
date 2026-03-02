# The 5 Approaches for Ruby Parsing

This document explains the different ways to parse using Parslet/Parsanol
and the performance characteristics of each approach.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    5 APPROACHES FOR RUBY PARSING                                 │
│                                                                                 │
│   Each approach moves more work from Ruby to Rust, increasing performance.     │
│   Measured with Expressir parsing EXPRESS schemas (22KB file).                 │
└─────────────────────────────────────────────────────────────────────────────────┘


╔═════════════════════════════════════════════════════════════════════════════════╗
║  APPROACH 1: Parslet Ruby (BASELINE)                                            ║
╠═════════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                      ║
║   │   INPUT     │     │  PARSLET    │     │   OUTPUT    │                      ║
║   │   String    │────▶│  (Ruby)     │────▶│  Ruby Hash  │                      ║
║   └─────────────┘     └─────────────┘     └─────────────┘                      ║
║                              │                                                  ║
║                         SLOW parsing                                             ║
║                         Pure Ruby                                                ║
║                                                                                 ║
║   SPEED: 1x (baseline) - 3036ms                                                 ║
╚═════════════════════════════════════════════════════════════════════════════════╝


╔═════════════════════════════════════════════════════════════════════════════════╗
║  APPROACH 2: Parsanol Ruby                                                      ║
╠═════════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                      ║
║   │   INPUT     │     │  PARSANOL   │     │   OUTPUT    │                      ║
║   │   String    │────▶│  (Ruby)     │────▶│  Ruby Hash  │                      ║
║   └─────────────┘     └─────────────┘     └─────────────┘                      ║
║                                                                                 ║
║   SPEED: ~1x (equivalent to Parslet)                                           ║
╚═════════════════════════════════════════════════════════════════════════════════╝


╔═════════════════════════════════════════════════════════════════════════════════╗
║  APPROACH 3: Parsanol Native (Batch)                                            ║
╠═════════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                      ║
║   │   INPUT     │     │  PARSANOL   │     │   OUTPUT    │                      ║
║   │   String    │────▶│  (Rust)     │────▶│  Ruby Hash  │                      ║
║   └─────────────┘     └─────────────┘     └─────────────┘                      ║
║                              │                                                  ║
║                         FAST parsing                                             ║
║                         AST via u64 array                                        ║
║                                                                                 ║
║   SPEED: ~20x faster - 153ms                                                    ║
╚═════════════════════════════════════════════════════════════════════════════════╝


╔═════════════════════════════════════════════════════════════════════════════════╗
║  APPROACH 4: Parsanol Native (ZeroCopy)                                         ║
╠═════════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║   ┌─────────────┐     ┌─────────────────────────┐                              ║
║   │   INPUT     │     │        PARSANOL         │                              ║
║   │   String    │────▶│        (Rust FFI)       │────▶ Ruby Objects            ║
║   └─────────────┘     │  Direct construction    │                              ║
║                       └─────────────────────────┘                              ║
║                                                                                 ║
║   SPEED: ~25x faster                                                            ║
╚═════════════════════════════════════════════════════════════════════════════════╝


╔═════════════════════════════════════════════════════════════════════════════════╗
║  APPROACH 5: Parsanol Native (ZeroCopy + Slice) ← FASTEST + RECOMMENDED        ║
╠═════════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║   ┌─────────────┐     ┌─────────────────────────────────────┐                  ║
║   │   INPUT     │     │            PARSANOL                 │                  ║
║   │   String    │────▶│            (Rust)                   │────▶ Slice Objects║
║   └─────────────┘     │  Zero-copy + Source positions      │                  ║
║                       └─────────────────────────────────────┘                  ║
║                              │                                                  ║
║                         FASTEST parsing                                          ║
║                         Source position tracking                                 ║
║                         Parslet::Slice compatible                               ║
║                                                                                 ║
║   SPEED: ~29x faster - 106ms (28.7x vs baseline)                               ║
║   FEATURES: Preserves source positions for linters, IDEs, Expressir            ║
╚═════════════════════════════════════════════════════════════════════════════════╝


┌─────────────────────────────────────────────────────────────────────────────────┐
│                           PERFORMANCE COMPARISON                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   Approach 1 (parslet-ruby)        ████████████████████████████████  1x        │
│   Approach 2 (parsanol-ruby)       ████████████████████████████████  ~1x       │
│   Approach 3 (native-batch)        ████████████████████████████████████████ 20x │
│   Approach 4 (native-zerocopy)     █████████████████████████████████████████████████ 25x│
│   Approach 5 (zerocopy+slice)      ████████████████████████████████████████████████████████████████████ 29x│
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│                              WHEN TO USE EACH                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   Approach 1-2: Maximum compatibility, debugging, learning                      │
│   Approach 3:   Need Ruby objects with good performance                        │
│   Approach 4:   Maximum performance, no source positions needed                │
│   Approach 5:   Linters, IDEs, Expressir - BEST OVERALL                        │
│                 (Fastest + source position tracking)                            │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│                           SLICE SUPPORT (NEW)                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   InputRef nodes now return Slice objects with source position info:           │
│                                                                                 │
│   Before (plain strings):                                                       │
│     [{"word"=>"hello"}, " ", {"name"=>"world"}]                                │
│                                                                                 │
│   After (Slice objects):                                                        │
│     [{"word"=>"hello"@0}, " "@5, {"name"=>"world"@6}]                          │
│                                                                                 │
│   The @N notation shows the byte offset in the original input                  │
│   Parsanol::Slice is compatible with Parslet::Slice                            │
│                                                                                 │
│   Use cases:                                                                    │
│   • Linters - show precise error locations                                     │
│   • IDEs - go-to-definition, find-references                                   │
│   • Expressir - EXPRESS schema parsing with source tracking                    │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Running the Benchmarks

```bash
# Run all approaches
bundle exec ruby benchmark/run_all.rb

# Run with verbose output to see which approach is being tested
bundle exec ruby benchmark/run_all.rb --verbose

# Quick mode (skip large inputs)
bundle exec ruby benchmark/run_all.rb --quick
```

## Implementation Status

| Approach | Ruby Method | Rust Function | Status |
|----------|-------------|---------------|--------|
| 1 | `Parslet::Parser#parse` | N/A | ✅ Available |
| 2 | `Parsanol::Parser#parse` (ruby backend) | N/A | ✅ Available |
| 3 | `Parsanol::Parser#parse` (rust backend) | `parse_batch()` | ✅ Available |
| 4 | `Parsanol::Native.parse_to_objects()` | `parse_to_objects()` | ✅ Available |
| 5 | `Parsanol::Native.parse_to_objects(slice: true)` | `parse_to_objects_with_slice()` | ✅ Available |

## Evidence-Based Results

Actual benchmark results from Expressir parsing EXPRESS schemas:

| Test File | Size | Lines | Parslet | Native Batch | ZeroCopy+Slice |
|-----------|------|-------|---------|--------------|----------------|
| geometry_schema.exp | 22KB | 733 | 3036ms | 153ms (19.9x) | 106ms (28.7x) |

**Run the benchmarks yourself to verify on YOUR machine!**
