# Implementation Plan: Capture, Scope, Dynamic FFI for parsanol-ruby

**Status**: Ready to implement
**Date**: March 2026
**Depends on**: parsanol-rs 0.3.0+ (already implemented)

## Executive Summary

parsanol-rs has implemented native support for `Capture`, `Scope`, and `Dynamic` atoms.
This document describes the Ruby FFI implementation needed to expose these features.

## Current State Analysis

### What Exists in parsanol-ruby

| Component | File | Status |
|-----------|------|--------|
| `Capture` atom | `atoms/capture.rb` | ✅ Works in Ruby mode |
| `Scope` atom | `atoms/scope.rb` | ✅ Works in Ruby mode |
| `Dynamic` atom | `atoms/dynamic.rb` | ✅ Works in Ruby mode |
| `serialize_capture` | `native/serializer.rb:201` | ❌ Stub - no capture semantics |
| `serialize_scope` | `native/serializer.rb:209` | ❌ Stub - no scope semantics |
| `serialize_dynamic` | `native/serializer.rb:225` | ❌ Fails with marker |

### What Exists in parsanol-rs

| Component | Status |
|-----------|--------|
| `Atom::Capture` | ✅ Implemented |
| `Atom::Scope` | ✅ Implemented |
| `Atom::Dynamic` | ✅ Implemented |
| `DynamicCallback` trait | ✅ Implemented |
| `register_dynamic_callback` FFI | ✅ Implemented |
| `CaptureState` | ✅ Implemented |
| Streaming parser with captures | ✅ Implemented |

## Implementation Plan

### Phase 1: Update Serializer (30 minutes)

Update `lib/parsanol/native/serializer.rb`:

```ruby
# BEFORE (lines 201-236)
def serialize_capture(atom)
  # Just serialized inner atom - no capture semantics
  serialize_atom(atom.parslet)
end

# AFTER
def serialize_capture(atom)
  {
    'Capture' => {
      'name' => atom.capture_key.to_s,
      'atom' => serialize_atom(atom.inner_atom)
    }
  }
end

# BEFORE
def serialize_scope(atom)
  inner = atom.block.call rescue nil
  if inner
    serialize_atom(inner)
  else
    serialize_unknown(atom)
  end
end

# AFTER
def serialize_scope(atom)
  inner = atom.block.call rescue nil
  return serialize_unknown(atom) unless inner

  {
    'Scope' => {
      'atom' => serialize_atom(inner)
    }
  }
end

# BEFORE
def serialize_dynamic(_atom)
  # Marker that fails at parse time
  {
    'Str' => {
      'pattern' => "\x00__DYNAMIC_NOT_SUPPORTED__"
    }
  }
end

# AFTER
def serialize_dynamic(atom)
  # Register the Ruby block and get a callback ID
  callback_id = Parsanol::Native::Dynamic.register(atom.block)

  {
    'Dynamic' => {
      'callback_id' => callback_id
    }
  }
end
```

### Phase 2: Dynamic Callback Registry (1 hour)

Create `lib/parsanol/native/dynamic.rb`:

```ruby
# frozen_string_literal: true

require 'json'

module Parsanol
  module Native
    # Manages Ruby callbacks for dynamic atoms
    #
    # Ruby blocks are registered here and assigned a unique ID.
    # The Rust parser calls back via FFI to invoke the block.
    #
    # Thread Safety: This module is thread-safe. Callbacks can be
    # registered and invoked from multiple threads simultaneously.
    #
    module Dynamic
      # Callback registry (callback_id => block)
      @callbacks = {}
      @next_id = 1_000_000
      @mutex = Mutex.new

      class << self
        # Register a Ruby block as a dynamic callback
        #
        # @param block [Proc] The block to register
        # @return [Integer] Unique callback ID for use in grammar
        #
        # Example:
        #   callback_id = Parsanol::Native::Dynamic.register(proc { |ctx| str('a') })
        #
        def register(block)
          @mutex.synchronize do
            id = @next_id
            @next_id += 1
            @callbacks[id] = block
            id
          end
        end

        # Unregister a callback (free memory)
        #
        # @param callback_id [Integer] The callback ID to remove
        #
        def unregister(callback_id)
          @mutex.synchronize do
            @callbacks.delete(callback_id)
          end
        end

        # Invoke a callback (called from Rust via FFI)
        #
        # @param callback_id [Integer] The callback ID
        # @param position [Integer] Current position in input
        # @param captures_json [String] JSON string of current captures
        # @return [String, nil] JSON string of atom to parse, or nil to fail
        #
        def invoke(callback_id, position, captures_json)
          block = @mutex.synchronize { @callbacks[callback_id] }
          return nil unless block

          # Parse captures from JSON
          captures = JSON.parse(captures_json) rescue {}

          # Build context object
          context = DynamicContext.new(position, captures)

          # Call the Ruby block
          result = block.call(context)

          return nil unless result

          # Serialize the returned atom
          GrammarSerializer.serialize(result)
        rescue StandardError => e
          # Log error but don't crash the parser
          warn "[Parsanol::Native::Dynamic] Callback error: #{e.message}"
          nil
        end

        # Get number of registered callbacks (for debugging)
        #
        # @return [Integer] Number of registered callbacks
        #
        def size
          @mutex.synchronize { @callbacks.size }
        end

        # Clear all callbacks (for testing)
        #
        def clear
          @mutex.synchronize { @callbacks.clear }
        end
      end
    end

    # Context object passed to dynamic callbacks
    #
    # Provides access to the current parsing state including
    # position and any captures made so far.
    #
    class DynamicContext
      attr_reader :position, :captures

      def initialize(position, captures)
        @position = position
        @captures = captures.transform_keys(&:to_sym)
      end

      # Get a capture by name
      #
      # @param name [Symbol, String] The capture name
      # @return [String, nil] The captured value or nil
      #
      def [](name)
        @captures[name.to_sym]
      end
    end
  end
end
```

### Phase 3: Rust FFI Integration (2 hours)

The Rust side needs to call back into Ruby. This requires:

1. **FFI function registration** in `ffi/ruby/dynamic.rs` (Rust side):

```rust
use magnus::{Error, Ruby, Value};
use crate::portable::capture::CaptureState;
use crate::portable::grammar::Atom;

/// Ruby dynamic callback wrapper
pub struct RubyDynamicCallback {
    proc: Value,
}

impl DynamicCallback for RubyDynamicCallback {
    fn resolve(&self, input: &str, pos: usize, captures: &CaptureState) -> Option<Atom> {
        let ruby = Ruby::get().ok()?;

        // Build Ruby hash from captures
        let captures_hash = ruby.hash_new();
        for (name, value) in captures.all_captures() {
            let slice = create_slice_object(&ruby, input, value.offset, value.length);
            let _ = captures_hash.aset(name.as_str(), slice);
        }

        // Call Ruby proc: proc.call(pos, captures_hash)
        let result: Value = self.proc
            .funcall("call", (pos, captures_hash))
            .ok()?;

        // Convert result back to Atom via JSON
        ruby_value_to_atom(&ruby, result)
    }
}

/// Register a Ruby proc as a dynamic callback
pub fn register_ruby_dynamic(proc: Value) -> Result<u64, Error> {
    let callback = RubyDynamicCallback { proc };
    Ok(register_dynamic_callback(Box::new(callback)))
}
```

2. **Ruby-side FFI wrapper** in `lib/parsanol/native.rb`:

```ruby
# Add to the Native module
module Parsanol
  module Native
    # ... existing code ...

    # Dynamic callback registration
    # Called from Rust when a dynamic atom needs resolution
    def self.invoke_dynamic_callback(callback_id, position, captures_json)
      Dynamic.invoke(callback_id, position, captures_json)
    end
  end
end
```

### Phase 4: Result Inspection API (30 minutes)

Add capture extraction methods to parse results:

```ruby
# In lib/parsanol/result.rb or similar

module Parsanol
  class ParseResult
    # Get all capture names from the result
    #
    # @return [Array<Symbol>] List of capture names
    #
    def capture_names
      extract_capture_names(@ast)
    end

    # Get a specific capture by name
    #
    # @param name [Symbol, String] The capture name
    # @return [String, nil] The captured value
    #
    def get_capture(name)
      captures[name.to_sym]
    end

    # Get all captures as a hash
    #
    # @return [Hash<Symbol, String>] All captures
    #
    def captures
      @captures ||= extract_captures(@ast)
    end

    private

    def extract_capture_names(ast)
      return [] unless ast.is_a?(Hash)

      names = []
      # Look for capture markers in the AST
      extract_names_recursive(ast, names)
      names.uniq
    end

    def extract_names_recursive(node, names)
      case node
      when Hash
        if node.key?('_capture')
          names << node['_capture'].to_sym
        end
        node.each_value { |v| extract_names_recursive(v, names) }
      when Array
        node.each { |item| extract_names_recursive(item, names) }
      end
    end

    def extract_captures(ast)
      result = {}
      extract_captures_recursive(ast, result)
      result
    end

    def extract_captures_recursive(node, result)
      case node
      when Hash
        if node.key?('_capture') && node.key?('_value')
          result[node['_capture'].to_sym] = node['_value']
        end
        node.each_value { |v| extract_captures_recursive(v, result) }
      when Array
        node.each { |item| extract_captures_recursive(item, result) }
      end
    end
  end
end
```

### Phase 5: DSL Integration (15 minutes)

Ensure DSL methods work with native mode:

```ruby
# In lib/parsanol/atoms/dsl.rb (already exists, verify it works)

module Parsanol
  module Atoms
    module DSL
      # Capture the result of parsing
      #
      # @param name [Symbol, String] Name for the capture
      # @return [Parsanol::Atoms::Capture] Capture atom
      #
      def capture(name)
        Capture.new(self, name)
      end

      # Create an isolated capture scope
      #
      # @param block [Proc] Block containing the scoped parser
      # @return [Parsanol::Atoms::Scope] Scope atom
      #
      def scope(&block)
        Scope.new(block)
      end

      # Dynamic parser selection at runtime
      #
      # @param block [Proc] Block returning a parser
      # @return [Parsanol::Atoms::Dynamic] Dynamic atom
      #
      def dynamic(&block)
        Dynamic.new(block)
      end
    end
  end
end
```

### Phase 6: Testing (1 hour)

Create `spec/parsanol/native/capture_scope_dynamic_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Parsanol::Native Capture, Scope, Dynamic' do
  before(:all) do
    skip 'Native extension not available' unless Parsanol::Native.available?
  end

  describe 'Capture atoms' do
    it 'captures matched text' do
      grammar = str('hello').capture(:greeting)
      result = Parsanol::Native.parse_with_grammar(grammar, 'hello world')
      expect(result).to be_success
      expect(result.get_capture(:greeting)).to eq('hello')
    end

    it 'captures work in sequences' do
      grammar = str('a').capture(:first) >> str('b').capture(:second)
      result = Parsanol::Native.parse_with_grammar(grammar, 'ab')
      expect(result).to be_success
      expect(result.get_capture(:first)).to eq('a')
      expect(result.get_capture(:second)).to eq('b')
    end

    it 'captures are discarded on backtracking' do
      grammar = (str('a').capture(:x) >> str('x')) | str('ab')
      result = Parsanol::Native.parse_with_grammar(grammar, 'ab')
      expect(result).to be_success
      expect(result.get_capture(:x)).to be_nil
    end
  end

  describe 'Scope atoms' do
    it 'isolates captures within scope' do
      grammar = scope { str('inner').capture(:x) } >> str('outer')
      result = Parsanol::Native.parse_with_grammar(grammar, 'innerouter')
      expect(result).to be_success
      expect(result.get_capture(:x)).to be_nil
    end

    it 'allows nested scopes' do
      grammar = scope {
        str('a').capture(:outer) >>
        scope { str('b').capture(:inner) }
      }
      result = Parsanol::Native.parse_with_grammar(grammar, 'ab')
      expect(result).to be_success
      expect(result.get_capture(:outer)).to be_nil
      expect(result.get_capture(:inner)).to be_nil
    end
  end

  describe 'Dynamic atoms' do
    it 'invokes callback at parse time' do
      grammar = dynamic { str('a') }
      result = Parsanol::Native.parse_with_grammar(grammar, 'a')
      expect(result).to be_success
    end

    it 'receives capture context' do
      grammar = str('MODE:').capture(:mode) >>
                dynamic { |ctx| ctx[:mode] == 'A' ? str('alpha') : str('beta') }
      result = Parsanol::Native.parse_with_grammar(grammar, 'MODE:alpha')
      expect(result).to be_success
    end

    it 'fails gracefully on callback error' do
      grammar = dynamic { raise "error" }
      result = Parsanol::Native.parse_with_grammar(grammar, 'anything')
      expect(result).to be_failure
    end
  end

  describe 'Cross-backend parity' do
    it 'produces same results for capture in both backends' do
      grammar = str('test').capture(:name)

      # Ruby mode
      ruby_result = grammar.parse('test')

      # Native mode
      native_result = Parsanol::Native.parse_with_grammar(grammar, 'test')

      expect(ruby_result.get_capture(:name)).to eq(native_result.get_capture(:name))
    end
  end
end
```

## File Changes Summary

| File | Change | Priority |
|------|--------|----------|
| `native/serializer.rb` | Update 3 methods | High |
| `native/dynamic.rb` | **NEW** - Callback registry | High |
| `native.rb` | Add `invoke_dynamic_callback` | High |
| `result.rb` | Add capture inspection methods | Medium |
| `spec/.../capture_scope_dynamic_spec.rb` | **NEW** - Tests | High |

## Estimated Time

| Phase | Duration |
|-------|----------|
| Phase 1: Serializer | 30 min |
| Phase 2: Dynamic Registry | 1 hour |
| Phase 3: Rust FFI | 2 hours |
| Phase 4: Result API | 30 min |
| Phase 5: DSL | 15 min |
| Phase 6: Testing | 1 hour |
| **Total** | **5-6 hours** |

## Dependencies

- [x] parsanol-rs 0.3.0+ with Capture, Scope, Dynamic support
- [ ] Rust FFI function `register_ruby_dynamic` (needs implementation)
- [ ] Rust FFI callback mechanism (needs implementation)

## Open Questions

1. **Callback lifetime**: Should callbacks be automatically unregistered when grammar is GC'd?
2. **Error handling**: Should callback errors be silently swallowed or propagated?
3. **Streaming + Dynamic**: How does dynamic work with streaming parser?

## Success Criteria

- [ ] `serialize_capture` produces valid `Capture` JSON
- [ ] `serialize_scope` produces valid `Scope` JSON
- [ ] `serialize_dynamic` registers callback and produces valid `Dynamic` JSON
- [ ] Dynamic callbacks are invoked from Rust at parse time
- [ ] Captures are extractable from parse results
- [ ] All tests pass
- [ ] Cross-backend parity verified
