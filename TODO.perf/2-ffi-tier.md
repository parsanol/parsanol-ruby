# 2 — FFI tier: universal native via a plain C ABI

Status: SUPERSEDED by TODO.perf/9 — the cdylib C-ABI tier shipped
(2026-09-15, rs #61 + ruby #34 -> 1.3.17) and is validated. This file
keeps the original design rationale. Remaining packaging items live in
TODO.perf/9.

## Goal

Give JRuby and TruffleRuby native parse speed and shrink the release matrix
by exposing parsanol-rs's portable core as a **plain C library** (no magnus,
no rb-sys, no Ruby headers) driven from Ruby through the `ffi` gem (JFFI on
JRuby). Model: nokogiri's `-java` gem.

Tiering in `Parser#parse`:

    magnus fast path (MRI platform gems)
      → ffi binding over libparsanol (JRuby/TruffleRuby, MRI without ext)
        → pure Ruby engine (universal floor)

## Why this matters beyond portability

- Today every platform gem is built against 4 Ruby versions because the
  extension links CRuby headers; magnus also imports version-coupled symbols
  (`rb_debug_inspector_*_depth`). A plain C library has **zero Ruby-version
  coupling**: one artifact per OS/arch instead of 10 × 4 builds, and the
  whole class of magnus/rb-sys sync breakage disappears for this tier.
- JRuby/TruffleRuby currently get the pure-Ruby fallback (~1.2x parslet);
  this tier should reach ~5–10x on real inputs (Rust parse dominates; only
  result decode runs in Ruby).

## Work items

1. parsanol-rs:
   - Promote `ffi/c.rs` to the supported C ABI. Ensure the exposed functions
     are `#[no_mangle] pub extern "C"` and stable/semver'd:
     `parsanol_grammar_new(json, len) -> handle`,
     `parsanol_parse(handle, input, len, out_ptr) -> status`,
     `parsanol_parse_batch(...)`, `parsanol_free_grammar(handle)`.
   - New crate target `cdylib` WITHOUT the `ruby` feature (pure core).
   - Keep error reporting C-friendly (status + error buffer, no panics).
2. parsanol-ruby:
   - `lib/parsanol/native/ffi_binding.rb` using the `ffi` gem (works on
     MRI + JRuby + TruffleRuby; add `ffi` as an optional dependency so the
     default gem stays dependency-free when only the magnus tier exists).
   - Library discovery order: env var, gem vendor dir, system path.
   - Batch result decode: read the u64 array with one `unpack("Q*")`, then
     the existing `BatchDecoder`/`AstTransformer` produce the Ruby tree.
   - Tier selection in `Native.available?`/`Parser#parse_native`.
3. Packaging:
   - Platform gems vendor `libparsanol.{so,dylib,dll}` per OS/arch.
   - `-java` platform gem: one gem, several vendored binaries, chosen by
     `RUBY_PLATFORM`/`os` at require time (nokogiri model).
4. CI: build + smoke the plain library on the platform matrix.

## Constraints

- The ffi tier's decode is slower than magnus materialization (Ruby-side
  object building). It is the *portability* tier, not the MRI speed tier.
- The crates.io publish blocker (magnus ^0.9 not on crates.io) is unchanged
  by this; the plain cdylib does not need magnus, but `cargo publish`
  verifies optional deps too. Resolution still waits on magnus 0.9 or a
  maintainer decision to drop the version requirement.
