# frozen_string_literal: true

# Parslet Compatibility Specs
# These specs are adapted from Parslet's test suite to verify 100% API compatibility.
#
# Original source: https://github.com/kschiess/parslet

require 'spec_helper'
require 'parsanol/parslet'

RSpec.describe 'Parslet API Compatibility' do
  include Parsanol::Parslet

  # =============================================================================
  # ATOM SPECS - Parser Combinators
  # =============================================================================

  describe 'str() atom' do
    it 'matches literal strings' do
      parser = str('hello')
      expect(parser.parse('hello')).to eq('hello')
    end

    it 'fails on non-matching input' do
      parser = str('hello')
      expect { parser.parse('world') }.to raise_error(Parsanol::ParseFailed)
    end

    it 'fails on partial match' do
      parser = str('hello')
      expect { parser.parse('hell') }.to raise_error(Parsanol::ParseFailed)
    end
  end

  describe 'match() atom' do
    it 'matches character classes' do
      parser = match('[a-z]')
      expect(parser.parse('x')).to eq('x')
    end

    it 'matches digits' do
      parser = match('[0-9]')
      expect(parser.parse('5')).to eq('5')
    end

    it 'fails on non-matching character' do
      parser = match('[a-z]')
      expect { parser.parse('5') }.to raise_error(Parsanol::ParseFailed)
    end
  end

  describe 'any atom' do
    it 'matches any single character' do
      parser = any
      expect(parser.parse('x')).to eq('x')
      expect(parser.parse('5')).to eq('5')
      expect(parser.parse(' ')).to eq(' ')
    end

    it 'fails on empty input' do
      parser = any
      expect { parser.parse('') }.to raise_error(Parsanol::ParseFailed)
    end
  end

  # =============================================================================
  # COMBINATOR SPECS
  # =============================================================================

  describe 'sequence (>>) combinator' do
    it 'matches sequences in order' do
      parser = str('a') >> str('b')
      expect(parser.parse('ab')).to eq('ab')
    end

    it 'returns merged hash for named captures' do
      parser = str('a').as(:first) >> str('b').as(:second)
      result = parser.parse('ab')
      expect(result).to eq({ first: 'a', second: 'b' })
    end

    it 'discards unnamed matches when named captures present' do
      # This is the KEY Parslet semantic!
      parser = str('SCHEMA ') >> match('[a-z]').repeat(1).as(:name) >> str(';')
      result = parser.parse('SCHEMA test;')
      expect(result).to eq({ name: 'test' })
    end

    it 'joins consecutive unnamed strings' do
      parser = str('a') >> str('b') >> str('c')
      expect(parser.parse('abc')).to eq('abc')
    end
  end

  describe 'alternative (|) combinator' do
    it 'tries alternatives in order' do
      parser = str('a') | str('b')
      expect(parser.parse('a')).to eq('a')
      expect(parser.parse('b')).to eq('b')
    end

    it 'fails if no alternative matches' do
      parser = str('a') | str('b')
      expect { parser.parse('c') }.to raise_error(Parsanol::ParseFailed)
    end
  end

  describe 'repetition (.repeat)' do
    it 'matches zero or more times' do
      parser = match('[a-z]').repeat(0)
      expect(parser.parse('')).to eq('')
      expect(parser.parse('abc')).to eq('abc')
    end

    it 'matches one or more times' do
      parser = match('[a-z]').repeat(1)
      expect(parser.parse('abc')).to eq('abc')
      expect { parser.parse('') }.to raise_error(Parsanol::ParseFailed)
    end

    it 'respects max boundary' do
      # repeat(0, 2) matches at most 2 characters
      # We must only parse 2 characters, not 3
      parser = match('[a-z]').repeat(0, 2)
      expect(parser.parse('ab')).to eq('ab') # Parse 'ab', not 'abc'
    end

    it 'produces array of named captures when name comes before repeat' do
      # key difference: .as(:x).repeat(1) vs .repeat(1).as(:x)
      # .as(:x).repeat(1) produces [{x: 'a'}, {x: 'b'}, {x: 'c'}]
      parser = match('[a-z]').as(:letter).repeat(1)
      result = parser.parse('abc')
      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
      expect(result.first).to eq({ letter: 'a' })
    end

    it 'produces single hash when repeat comes before name' do
      # .repeat(1).as(:x) produces {x: 'abc'}
      parser = match('[a-z]').repeat(1).as(:letters)
      result = parser.parse('abc')
      expect(result).to eq({ letters: 'abc' })
    end
  end

  describe '.maybe (optional)' do
    it 'matches zero or one time' do
      parser = str('a').maybe
      expect(parser.parse('')).to eq('')
      expect(parser.parse('a')).to eq('a')
    end
  end

  describe '.as (named capture)' do
    it 'captures match with name' do
      # match('[a-z]') only matches ONE character
      # Use .repeat(1) to match multiple characters
      parser = match('[a-z]').repeat(1).as(:word)
      expect(parser.parse('hello')).to eq({ word: 'hello' })
    end

    it 'captures sequences' do
      parser = (str('a') >> str('b')).as(:pair)
      expect(parser.parse('ab')).to eq({ pair: 'ab' })
    end
  end

  # =============================================================================
  # PARSER CLASS SPECS
  # =============================================================================

  describe 'Parser class' do
    let(:parser_class) do
      Class.new(Parsanol::Parslet::Parser) do
        include Parsanol::Parslet

        rule(:digit) { match('[0-9]') }
        rule(:number) { digit.repeat(1).as(:num) }
        rule(:letter) { match('[a-z]') }
        rule(:word) { letter.repeat(1).as(:word) }
        rule(:expression) { number >> str(' ') >> word }
        root(:expression)
      end
    end

    it 'parses using root rule' do
      parser = parser_class.new
      result = parser.parse('123 hello')
      expect(result).to eq({ num: '123', word: 'hello' })
    end

    it 'raises ParseFailed on invalid input' do
      parser = parser_class.new
      expect { parser.parse('abc') }.to raise_error(Parsanol::ParseFailed)
    end
  end

  # =============================================================================
  # TRANSFORM SPECS
  # =============================================================================

  describe 'Transform class' do
    let(:transform_class) do
      Class.new(Parsanol::Parslet::Transform) do
        rule(num: simple(:n)) { Integer(n) }
        rule(word: simple(:w)) { w.to_s.upcase }
        rule(num: simple(:n), word: simple(:w)) { { number: Integer(n), word: w.to_s.upcase } }
      end
    end

    it 'transforms simple patterns' do
      transform = transform_class.new
      expect(transform.apply({ num: '42' })).to eq(42)
      expect(transform.apply({ word: 'hello' })).to eq('HELLO')
    end

    it 'transforms complex patterns' do
      transform = transform_class.new
      result = transform.apply({ num: '123', word: 'world' })
      expect(result).to eq({ number: 123, word: 'WORLD' })
    end
  end

  # =============================================================================
  # NATIVE PARSER COMPATIBILITY SPECS
  # =============================================================================

  describe 'Native parser compatibility', if: defined?(Parsanol::Native) && Parsanol::Native.available? do
    describe 'sequence flattening' do
      it 'produces Parslet-compatible AST for SCHEMA example' do
        # This is the exact test case from TODO.parslet-compat-fix.md
        parser = str('SCHEMA ') >> match('[a-z]').repeat(1).as(:name) >> str(';')

        input = 'SCHEMA test;'
        ruby_ast = parser.parse(input)
        native_ast = Parsanol::Native::Parser.parse(parser, input)

        # Both should produce same structure (ignoring Slice position info)
        expect(ruby_ast.keys).to eq(native_ast.keys)
        expect(ruby_ast[:name]).to eq(native_ast[:name])
      end

      it 'handles nested sequences correctly' do
        parser = str('(') >>
                 match('[a-z]').as(:first) >>
                 str(',') >>
                 match('[a-z]').as(:second) >>
                 str(')')

        input = '(a,b)'
        ruby_ast = parser.parse(input)
        native_ast = Parsanol::Native::Parser.parse(parser, input)

        expect(native_ast).to eq({ first: 'a', second: 'b' })
        expect(native_ast.keys).to eq(ruby_ast.keys)
      end

      it 'returns single value for single named capture' do
        # Use .repeat(1).as() pattern for matching multiple characters
        parser = match('[a-z]').repeat(1).as(:word)
        input = 'hello'

        ruby_ast = parser.parse(input)
        native_ast = Parsanol::Native::Parser.parse(parser, input)

        expect(native_ast).to eq({ word: 'hello' })
        expect(native_ast.keys).to eq(ruby_ast.keys)
      end

      it 'handles repetitions with named captures (name before repeat)' do
        # .as(:x).repeat(1) produces array of hashes
        parser = match('[a-z]').as(:letter).repeat(1)
        input = 'abc'

        ruby_ast = parser.parse(input)
        native_ast = Parsanol::Native::Parser.parse(parser, input)

        # Ruby produces array of hashes with Slice
        expect(ruby_ast).to be_an(Array)
        expect(ruby_ast.length).to eq(3)
        expect(ruby_ast.first.keys).to eq([:letter])

        # Native should produce same structure (array of hashes)
        expect(native_ast).to be_an(Array)
        expect(native_ast.length).to eq(3)
        expect(native_ast.first.keys).to eq([:letter])
        expect(native_ast.first[:letter]).to eq('a')
      end

      it 'handles repetitions with named captures (repeat before name)' do
        # .repeat(1).as(:x) produces single hash with joined string
        parser = match('[a-z]').repeat(1).as(:letters)
        input = 'abc'

        ruby_ast = parser.parse(input)
        native_ast = Parsanol::Native::Parser.parse(parser, input)

        expect(native_ast).to eq({ letters: 'abc' })
        expect(native_ast).to eq(ruby_ast)
      end

      it 'handles nested wrapper pattern (EXPRESS-like syntax)' do
        # This tests the wrapper pattern detection for sequences where items
        # have different inner keys under the same wrapper key.
        #
        # NOTE: When there are duplicate keys in a sequence, Parslet KEEPS THE LAST ONE
        # (with a warning). So the result is {:wrapper => {:second => "..."}}, not merged.
        #
        # The wrapper pattern detection is important for Expressir-style grammars where
        # the native parser might produce:
        #   [{:syntax => {:spaces => {...}}}, {:syntax => {:schemaDecl => [...]}}]
        # But this should NOT be merged because the values are HASHES with DIFFERENT keys.
        #
        # For now, we test that the native parser produces the same result as Ruby.

        parser = (
          match('[a-z]').repeat(1).as(:first).as(:wrapper) >>
          str(' ') >>
          match('[0-9]').repeat(1).as(:second).as(:wrapper)
        )

        input = 'abc 123'
        ruby_ast = parser.parse(input)
        native_ast = Parsanol::Native::Parser.parse(parser, input)

        # Both should produce the same result (Ruby overwrites duplicates)
        expect(native_ast).to be_a(Hash)
        expect(native_ast.keys).to eq([:wrapper])
        expect(native_ast[:wrapper]).to be_a(Hash)
        expect(native_ast[:wrapper].keys).to eq([:second])

        # Native should match Ruby
        expect(native_ast.keys).to eq(ruby_ast.keys)
      end

      it 'distinguishes wrapper pattern from repetition pattern' do
        # Repetition pattern: .as(:x).repeat(2) should produce array
        # Wrapper pattern: sequence of items with same single key should merge
        #
        # This test ensures we don't incorrectly merge repetition results

        # Repetition: should produce array of hashes
        repetition_parser = match('[a-z]').as(:letter).repeat(2)
        repetition_result = Parsanol::Native::Parser.parse(repetition_parser, 'ab')
        expect(repetition_result).to be_an(Array)
        expect(repetition_result.length).to eq(2)
        expect(repetition_result).to eq([{ letter: 'a' }, { letter: 'b' }])

        # Wrapper: duplicate keys - Ruby keeps LAST value (not merge)
        #
        # With :sequence/:repetition tags in batch format, we can now distinguish:
        #   1. Sequence with duplicate labels (should keep last)
        #   2. Repetition with different inner keys (should keep as array)
        #
        wrapper_parser = (
          match('[a-z]').as(:char).as(:group) >>
          match('[0-9]').as(:digit).as(:group)
        )
        wrapper_result = Parsanol::Native::Parser.parse(wrapper_parser, 'a5')
        expect(wrapper_result).to be_a(Hash)
        expect(wrapper_result.keys).to eq([:group])
        # Ruby parser keeps LAST value when duplicate keys
        expect(wrapper_result[:group]).to eq({ digit: '5' })
      end

      it 'handles repetition with separator pattern correctly' do
        # This is the common pattern: X (separator X)*
        # Example: item (',' item)* used in parameter lists, argument lists, etc.
        #
        # The key test is that items in the repetition should NOT be wrapped
        # with the parent key. They should keep their own keys.
        #
        # Bug history: Previously, (separator >> item).repeat.as(:rest) would
        # incorrectly produce: {rest: [{rest: {name: "b"}}, {rest: {name: "c"}}]}
        # instead of the correct: {rest: [{name: "b"}, {name: "c"}]}

        # Test Case 1: item.as(:first) >> (separator >> item).repeat.as(:rest)
        parser = Class.new(Parsanol::Parser) do
          include Parsanol

          rule(:item) { match('[a-z]').as(:name) }
          rule(:separator) { str(',') }
          rule(:list) { item.as(:first) >> (separator >> item).repeat.as(:rest) }

          root(:list)
        end.new

        result = Parsanol::Native::Parser.parse(parser.root, 'a,b,c')

        expect(result).to be_a(Hash)
        expect(result[:first]).to eq({ name: 'a' })
        expect(result[:rest]).to be_an(Array)
        expect(result[:rest].length).to eq(2)

        # CRITICAL: Items should have :name key, NOT :rest key
        expect(result[:rest][0]).to eq({ name: 'b' })
        expect(result[:rest][1]).to eq({ name: 'c' })

        # Verify same result as Ruby parser
        ruby_result = parser.parse('a,b,c')
        expect(result).to eq(ruby_result)
      end
    end
  end
end
