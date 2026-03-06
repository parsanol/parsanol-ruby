# Continuation Plan: parsanol-ruby

## Current State

### Completed (2026-03-06)
1. **FFI Bindings for Capture, Scope, Dynamic atoms** - FULLY IMPLEMENTED
   - Rust FFI callbacks working
   - Ruby DSL complete
   - All 1178 tests pass
   - Examples created
   - Website documentation updated

### Migration Status
- parsanol-rs dependency: Using path dependency at `0.2` (0.1.6 crates.io version is outdated)
- All features from 0.2.0 are accessible via FFI

## Remaining Work

### 1. Release Preparation
- [ ] Update `parsanol.gemspec` version to `1.2.0`
- [ ] Update `Cargo.lock` for final parsanol-rs 0.2 release
- [ ] Run full test suite on CI
- [ ] Create release notes

### 2. Documentation Updates
- [x] Update `README.adoc` with capture/scope/dynamic examples
- [ ] Add migration guide for Expressir users
- [ ] Document performance characteristics

### 3. Streaming Parser (Future)
- [ ] Verify `Parsanol::StreamingParser` works with native extension
- [ ] Add streaming examples to website
- [ ] Performance benchmarks for large files

### 4. Website Deployment
- [ ] Commit website changes
- [ ] Deploy to GitHub Pages
- [ ] Verify all links work

## Known Issues

1. **Dynamic callback performance**: Falls back to Packrat backend for Bytecode/Streaming. Consider documenting this limitation.

2. **Streaming captures**: The Ruby streaming parser requires native extension. Graceful fallback implemented but may need improvement.

3. **Capture API**: Result is a Slice when there's only one capture, Hash when multiple. This may be confusing for users.

## Architecture Notes

### Key Files
- `lib/parsanol/native/dynamic.rb` - Ruby callback registry
- `lib/parsanol/native/serializer.rb` - Grammar serialization
- `ext/parsanol_native/src/lib.rs` - Native extension entry point
- `parsanol-rs/` - Rust library (path dependency)

### Design Decisions
1. **Callback ID approach**: Rust stores only IDs, Ruby stores actual blocks. This avoids Send+Sync issues with magnus::Value.

2. **FFI boundary**: All dynamic callbacks go through `invoke_from_rust` which builds a DynamicContext from the Rust DynamicContext.

3. **Serialization**: Capture/scope/dynamic atoms are serialized to JSON for native parsing.

## Next Steps for Developer

1. **If releasing**:
   - Update version numbers
   - Run `bundle exec rake compile`
   - Run `bundle exec rspec`
   - Create git tag

2. **If continuing development**:
   - Check test coverage for new features
   - Add integration tests for complex capture/scope interactions
   - Profile performance with heavy dynamic usage

3. **If documenting**:
   - Add examples to README.adoc
   - Update API documentation
   - Create migration guide for users upgrading from 1.1.0
