# JSON (Ruby Transform - Option A)

## Purpose

This implementation demonstrates Parslet-compatible JSON parsing: Rust parses,
Ruby transforms into domain objects.

## When to Use

- Migrating from Parslet
- Custom JSON processing logic
- Flexible transformation needs

## Key Concepts

1. **Rust Parsing**: Fast native parsing engine
2. **Ruby Transform**: Familiar transformation API
3. **Custom Output**: Any Ruby object structure

## Running

```bash
ruby example/json/ruby_transform.rb
```

## Output

```
Input: {"key": "value"}
Parse tree: {object: [{string: "key", value: {string: "value"}}]}
Result: {"key" => "value"}
```
