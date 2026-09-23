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

1. DECIDED (2026-09-23); LAST MILE UNFINISHED — the twin crate
   (ext/parsanol_cdylib), the env-gated gemspec exception, the
   **/target/** glob rejection and the workflow triple map all landed,
   but the cdylib still does not reach the packaged gem: rake-compiler
   packages cross gems from tmp/<platform>/stage/, and no hook fired
   yet that both builds the cdylib in-dock AND stages it there
   (additive rake prerequisite: not invoked; cross-gem
   pre-setup-command: copies to the working tree, not the stage;
   cross_compiling callback: never invoked under rb-sys's env-driven
   cross flow). Next step: read rb_sys/extensiontask.rb for the seam
   where the platform spec is finalized and hook build+stage there.
   Experiments live on branch cross-gem/vendor-verify.
   Original design notes: the **ruby (source) gem stays
   binary-free**; each **platform gem vendors its own triple's cdylib**
   at `lib/parsanol/native/` (where `locate_library` already probes).
   Mechanism: `ext/parsanol_cdylib` (gem-workspace twin of parsanol-rs's
   parsanol-ffi, pure-portable — no magnus, zero Ruby-version coupling)
   built by `rake gem:vendor_cdylib` in the cross-gem jobs under
   `PARSANOL_VENDOR_CDYLIB=1`; the gemspec's binary rejection is scoped
   so a plain `gem build` can never vendor. MRI gains a resilience
   fallback (cdylib when the extension fails to load); TruffleRuby
   resolves its host-triple platform gem and gets the ffi tier natively;
   JRuby (java platform) keeps the pure-Ruby engine — a java companion
   gem is possible later if demanded. Also fixed here: the gemspec glob
   no longer admits `**/target/**` (a dirty local ext tree once
   inflated a build to 218 MB).
2. STILL OWNER CALL: hard `add_dependency "ffi"` vs the current
   soft-require (soft stands; ffi is a Gemfile dev dep for specs).
3. DONE (0.8.7): `parsanol_c_parse_len` — binary-safe input; the Ruby
   binding uses it exclusively and fails availability loudly on a stale
   cdylib.
4. OPEN: JRuby/TruffleRuby CI legs running the differential harnesses.
