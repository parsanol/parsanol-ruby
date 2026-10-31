# Upgrading a grammar to capture edition 2

Edition 2 is the fully named dialect: every rule reference that
produces no capture is wrapped in `Named(rule_name)`, so the tree
mirrors the grammar's rule structure. Edition 1 (the default) keeps
the legacy flat shapes. This guide is for consumers — grammar authors
whose models, builders, or mappers read parsanol trees — moving from
edition 1 to edition 2.

## The four steps

### 1. Pin the edition explicitly

```parg
grammar YourThing version "1.0.0" edition 2 {
```

The bare number is the canonical spelling. The quoted forms
(`edition "v2"`) remain; the pre-1.3.113 `mode` keyword was removed
accepted aliases for grammars written before the numeric surface.

Every grammar SHOULD pin its edition even while staying on edition 1:
the envelope records it, the loader asserts it, and the default can
never move under you again.

### 2. Run the migration radar

```
parsanol parg lint your-grammar.parg --captures
```

For an edition-1 grammar the radar reports exactly which reference
sites edition 2 would wrap — the complete list of tree nodes whose
shape changes. Whitespace glue is not reported: rules that can only
match whitespace are exempt from the wrap.

### 3. Declare the glue that eats more than whitespace

Some separators carry non-whitespace text (`;`, comments) or wrap
verbatim scans. Declare them and the wrap leaves them alone
(parsanol-ruby#364):

```parg
grammar YourThing version "1.0.0" edition 2 {
  glue whitespace line_comment block_comment
  ...
}
```

Declared rules stay anonymous — references to them and their own
bodies. Declare the whole chain: a comment rule's internal scan stays
anonymous only if the comment rule itself is declared.

### 4. Update the tree readers

Each radar entry is a node your builder will now see as
`{rule_name: <value>}` instead of a bare value. Two recurring cases:

- **Whitespace glue** (`space = " "`, `ws = %x20 / %x09`): rules
  whose body can only match whitespace are EXEMPT from the wrap — they
  stay anonymous, so gaps between atoms never appear as captures
  (parsanol-ruby#352).
- **Character runs** (`digit = %x30-39`, `number = 1*digit`): a named
  character rule repeats as an array of named captures. Builders that
  joined the raw text should scalarize the run (concatenate the
  values); parsanol's flatten laws keep a single-iteration case
  scalar.

### 5. Re-freeze and assert

Re-bake artifacts (the `edition` field and checksums change) and record
the edition alongside any frozen tree expectations. At load:

```ruby
artifact = Parsanol::PARG::Artifact.load(path)
raise "re-bake against edition 2" unless artifact.edition == 2
```

## Engine support

Edition-2 trees are byte-identical on every engine (ruby native +
interpreter, rs walker, rs VM, wasm, ts) — the cross-engine gates run
the wrapped shapes on every merge. Compile-time only: the wrap lowers
to ordinary `Named` atoms; nothing new crosses the wire.

## References

- ruby#304 (the dialect spec), ruby#352 (the whitespace exemption),
  ruby#357 (one axis: `edition`).
- `parg lint --captures` — the migration radar.
