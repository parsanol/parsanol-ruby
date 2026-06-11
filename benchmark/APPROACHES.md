# The 3 Approaches for Ruby Parsing

This document explains the different ways to parse using Parslet/Parsanol
and the performance characteristics of each approach.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    3 APPROACHES FOR RUBY PARSING                                 │
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
║  APPROACH 3: Parsanol Native (unified parse)                                    ║
╠═════════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                      ║
║   │   INPUT     │     │  PARSANOL   │     │   OUTPUT    │                      ║
║   │   String    │────▶│  (Rust)     │────▶│  Ruby Hash  │                      ║
║   └─────────────┘     └─────────────┘     └─────────────┘                      ║
║                              │                                                  ║
║                         FAST parsing                                             ║
║                         AST via u64 array                                        ║
║                         Slice leaves with lazy line/column                       ║
║                                                                                 ║
║   SPEED: ~20x faster - 153ms                                                    ║
╚═════════════════════════════════════════════════════════════════════════════════╝


┌─────────────────────────────────────────────────────────────────────────────────┐
│                           PERFORMANCE COMPARISON                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   Approach 1 (parslet-ruby)        ████████████████████████████████  1x        │
│   Approach 2 (parsanol-ruby)       ████████████████████████████████  ~1x       │
│   Approach 3 (parsanol-native)     ████████████████████████████████████████ 20x │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│                              WHEN TO USE EACH                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   Approach 1-2: Maximum compatibility, debugging, learning                      │
│   Approach 3:   Performance with Ruby objects and source positions             │
│                 (linters, IDEs, Expressir)                                      │
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
| 2 | `Parsanol::Parser#parse(mode: :ruby)` | N/A | ✅ Available |
| 3 | `Parsanol::Parser#parse(mode: :native)` | batch FFI | ✅ Available |

## Removed Approaches (history)

Earlier revisions described two further approaches: "ZeroCopy" built on a
dedicated `parse_to_objects` FFI entry point, and a "ZeroCopy + Slice"
variant. `parse_to_objects` was removed in parsanol-rs 0.4.0 ("Ruby FFI API
Simplification: Unified to single `parse()` function" —
`parse_to_objects(g, i, map)` → `parse(g, i)`), mirrored by parsanol-ruby
1.3.0's removal of the deprecated Ruby methods. The slice variant's dedicated
entry point (`parse_to_objects_with_slice`) appears only in earlier revisions
of this document — it never shipped in parsanol-rs. Both goals — direct Ruby
objects and Slice source positions — are served by today's unified `parse()`
(Approach 3). A development prototype of ZeroCopy + Slice measured 106ms
(28.7x vs Parslet) on the 22KB EXPRESS benchmark, which is why older notes
cite a faster fifth approach.

## Evidence-Based Results

Historical benchmark results from Expressir parsing EXPRESS schemas:

| Test File | Size | Lines | Parslet | Native Batch |
|-----------|------|-------|---------|--------------|
| geometry_schema.exp | 22KB | 733 | 3036ms | 153ms (19.9x) |

**Run the benchmarks yourself to verify on YOUR machine!**
