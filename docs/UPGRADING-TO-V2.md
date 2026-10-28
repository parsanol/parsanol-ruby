# Upgrading a grammar to capture mode v2

v2 is the fully named dialect: every rule reference that produces no
capture is wrapped in `Named(rule_name)`, so the tree mirrors the
grammar's rule structure. v1 (the default) keeps the legacy flat
shapes. This guide is for consumers — grammar authors whose models,
builders, or mappers read parsanol trees — moving from v1 to v2.

## The four steps

### 1. Pin the dialect explicitly

```parg
grammar YourThing version "1.0.0" mode "v2" {
```

Every grammar SHOULD pin its dialect even while staying on v1: the
envelope records it, the loader asserts it, and the default can never
move under you again.

### 2. Run the migration radar

```
parsanol parg lint your-grammar.parg --captures
```

For a v1 grammar the radar reports exactly which reference sites v2
would wrap — the complete list of tree nodes whose shape changes.

### 3. Update the tree readers

Each radar entry is a node your builder will now see as
`{rule_name: <value>}` instead of a bare value. Two recurring cases:

- **Whitespace glue** (`space = " "`, separators): rules whose body is
  whitespace-only are EXEMPT from the wrap — they stay anonymous, so
  gaps between atoms never appear as captures (parsanol-ruby#352).
- **Character runs** (`digit = %x30-39`, `number = 1*digit`): a named
  character rule repeats as an array of named captures. Builders that
  joined the raw text should scalarize the run (concatenate the
  values); parsanol's flatten laws keep a single-iteration case
  scalar.

### 4. Re-freeze and assert

Re-bake artifacts (the `mode` field and checksums change) and record
`emission`/`mode` alongside any frozen tree expectations. At load:

```ruby
artifact = Parsanol::PARG::Artifact.load(path)
raise "re-bake against v2" unless artifact.emission == 2 && artifact.envelope["mode"] == "v2"
```

## Engine support

v2 trees are byte-identical on every engine (ruby native + interpreter,
rs walker, rs VM, wasm, ts) — the cross-engine gates run the wrapped
shapes on every merge. Compile-time only: the wrap lowers to ordinary
`Named` atoms; nothing new crosses the wire.

## References

- ruby#304 (the dialect spec), ruby#352 (the whitespace exemption),
  ruby#353 (the emission/mode assertions at load).
- `parg lint --captures` — the migration radar.
