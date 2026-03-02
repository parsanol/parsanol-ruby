# JSON (Zero-Copy - Option C)

## Purpose

This implementation demonstrates direct FFI object construction for JSON
parsing without serialization overhead.

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
ruby example/json/zero_copy.rb
```

## Output

```
Input: {"key": "value"}
Result: Hash
Value: {"key" => "value"}
```

## Note

This is the fastest option but requires more complex FFI setup.
