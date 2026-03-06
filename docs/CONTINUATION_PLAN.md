# Continuation Plan: parsanol-ruby

## Current State

### Completed (2026-03-07)
1. **FFI Bindings for Capture, Scope, Dynamic atoms** - FULLY IMPLEMENTED
   - Rust FFI callbacks working
   - Ruby DSL complete
   - All 1178 tests pass
   - Examples created
   - Website documentation updated
   - Feature branch pushed: `feature/capture-scope-dynamic-ffi`

### Migration Status
- parsanol-rs dependency: Using git reference to `feat/capture-scope-dynamic-atoms` branch
- All features from 0.2.0 are accessible via FFI

## Remaining Work

### 1. Release Preparation
- [x] Update version to 1.2.0
- [x] Update Cargo.toml to use git reference for parsanol-rs
- [x] Run full test suite (1178 examples, 0 failures)
- [x] Fix rubocop offenses
- [ ] Create PR and merge to main
- [ ] Publish gem to RubyGems (after parsanol-rs 0.2.0 is published)

### 2. Documentation Updates
- [x] Update `README.adoc` with capture/scope/dynamic examples
- [x] Add migration guide for Expressir users
- [x] Document performance characteristics

### 3. Streaming Parser (Future)
- [ ] Implement Ruby FFI bindings for streaming parser
- [ ] Add streaming examples to website
- [ ] Performance benchmarks for large files

### 4. Website Deployment
- [x] Commit website changes (68c096e)
- [x] Push to GitHub (auto-deploys via GitHub Pages)
- [ ] Verify all links work after deployment

## Known Issues

1. **Dynamic callback performance**: Falls back to Packrat backend for Bytecode/Streaming. Documented in FFI_CAPTURE_SCOPE_DYNAMIC.md.

2. **Streaming parser**: Ruby FFI bindings not yet implemented. The `StreamingParser` class exists but requires native functions to be exposed.

3. **Capture API**: Result is a Slice when there's only one capture, Hash when multiple. This may be confusing for users.

## Architecture Notes

### Key Files
- `lib/parsanol/native/dynamic.rb` - Ruby callback registry
- `lib/parsanol/native/serializer.rb` - Grammar serialization
- `ext/parsanol_native/src/lib.rs` - Native extension entry point
- `parsanol-rs/` - Rust library (git reference)

### Design Decisions
1. **Callback ID approach**: Rust stores only IDs, Ruby stores actual blocks. This avoids Send+Sync issues with magnus::Value.

2. **FFI boundary**: All dynamic callbacks go through `invoke_from_rust` which builds a DynamicContext from the Rust DynamicContext.

3. **Serialization**: Capture/scope/dynamic atoms are serialized to JSON for native parsing.

## Next Steps for Developer

1. **If releasing**:
   - Create PR from `feature/capture-scope-dynamic-ffi` to `main`
   - Wait for parsanol-rs 0.2.0 to be published to crates.io
   - Update Cargo.toml to use version instead of git reference
   - Create git tag and publish gem

2. **If continuing development**:
   - Check test coverage for new features
   - Add integration tests for complex capture/scope interactions
   - Profile performance with heavy dynamic usage

3. **If documenting**:
   - Update API documentation
   - Create migration guide for users upgrading from 1.1.0 (done: MIGRATION_EXPRESSIR.md)
