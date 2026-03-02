# Calculator (Serialized - Option B)

## Purpose

This implementation demonstrates full Rust processing with JSON output:
Rust parses AND transforms, returning serialized JSON.

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
ruby example/calculator/serialized.rb
```

## Output

```
Input: 42+8
JSON: {"type":"AddExpr","left":{"type":"Number","value":42},"op":"+","right":{"type":"Number","value":8}}
Result: 50
```
