# CSV (Serialized - Option B)

## Purpose

This implementation demonstrates full Rust processing with JSON output
for CSV parsing.

## When to Use

- Cross-language compatibility
- Structured output required
- Performance-critical applications

## Key Concepts

1. **Rust Parsing + Transform**: All processing in Rust
2. **JSON Serialization**: Language-agnostic output
3. **Type Safety**: Schema-driven structure

## Running

```bash
ruby example/csv/serialized.rb
```

## Output

```
Input: a,b,c
JSON: [["a","b","c"]]
```
