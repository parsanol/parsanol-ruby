# Calculator (Ruby Transform - Option A)

## Purpose

This implementation demonstrates Parslet-compatible parsing: Rust parses the
input, Ruby transforms the result into domain objects.

## When to Use

- Migrating from Parslet
- Maximum flexibility in transformation
- When domain logic should stay in Ruby

## Key Concepts

1. **Rust Parsing**: Fast native parsing engine
2. **Ruby Transform**: Familiar Parslet::Transform API
3. **Flexible Output**: Any Ruby object structure

## Running

```bash
ruby example/calculator/ruby_transform.rb
```

## Output

```
Input: 42+8
Parse tree: {int: "42", op: "+", rhs: {int: "8"}}
Result: 50
```
