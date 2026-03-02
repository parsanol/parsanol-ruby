# Calculator (Zero-Copy - Option C)

## Purpose

This implementation demonstrates direct FFI object construction: Rust parses
and directly constructs Ruby objects without serialization.

## When to Use

- Maximum performance required
- Production systems
- When zero-copy is critical

## Key Concepts

1. **Direct FFI**: No serialization overhead
2. **Ruby Object Construction**: Direct via rb_funcall
3. **Type Safety**: Mirrored types on both sides

## Running

```bash
ruby example/calculator/zero_copy.rb
```

## Output

```
Input: 42+8
Result: Calculator::AddExpr
Value: 50
```

## Note

This is the fastest option but requires more complex FFI setup.
