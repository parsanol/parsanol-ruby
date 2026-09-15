# 9 — ffi-gem cdylib tier: the Rust engine on every runtime

Status: IMPLEMENTED + validated (2026-09-15); packaging automation pending

## Mandate

JRuby, TruffleRuby, and MRI-without-a-binary users still got the pure-Ruby
engine. The parsanol crate now also builds as a cdylib exporting a C ABI
(`crate-type = ["rlib", "cdylib"]`), bound from Ruby through the `ffi` gem
— one artifact family, every runtime.

## Design

- `parsanol_c_register(json) -> u64` / `parsanol_c_release(handle)` /
  `parsanol_c_parse(handle, input, out, cap) -> isize` /
  `parsanol_c_last_error()` in `ffi/c.rs`. Pure portable code, no magnus.
- Two-call buffer protocol: `cap=0` returns the needed size (negative),
  then one `FFI::MemoryPointer` carries the whole flat-u64 batch.
- `parsanol_c_parse` flattens the RAW tagged arena tree — NOT
  `to_parslet_compatible`'s pre-fold. The Ruby-side AstTransformer must
  see the same tagged shapes the extension path produces; pre-folding in
  Rust made the two backends build different trees (7566 pubid fixtures
  diverged; zero after removing it).
- Ruby side: `Parsanol::Native::Ffi` (soft-requires `ffi`). Library
  search: `PARSANOL_FFI_LIB`, gem-vendored `libparsanol.{dylib,so,dll}`
  next to the file, then system path. Handles cached by serialized
  grammar. `Native.available?` = MRI extension, else Ffi tier.
  Errors go through the same single reporter-pass fallback.

## Validation

- pubid ISO fixtures through Ffi.parse: 7576/7621 identical to parslet
  (45 fail in parslet too) — same numbers as the extension tier.
- asciichem: 16/16 valid inputs identical + 2 both-fail.
- `spec/parsanol/native/ffi_spec.rb` (4 examples).

## Learned the hard way

- `String::as_ptr()` on an empty static String is a dangling pointer —
  FFI callers segfault. Return the static `""` C string instead, and
  keep error buffers NUL-terminated.
- `finalize_result` must be public: cross-object recovery calls it.

## Remaining (packaging)

1. Release workflow: build the cdylib in the same rb-sys-dock matrix and
   vendor it into each platform gem (`lib/parsanol/native/`), plus a
   Ruby-platform fallback tarball. The local dylib used for validation
   is NOT committed.
2. Decide (owner call): hard `add_dependency "ffi"` vs the current
   soft-require.
3. NUL bytes in input truncate at the C-string boundary — add a
   length-taking variant if real workloads need binary inputs.
4. JRuby/TruffleRuby CI legs running the differential harnesses.
