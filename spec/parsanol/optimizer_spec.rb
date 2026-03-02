# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Optimizer do
  include Parsanol

  describe '.simplify_quantifiers' do
    context 'with trivial repetitions' do
      it 'unwraps repeat(1, 1) to just the inner parslet' do
        parser = str('a').repeat(1, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Str)
        expect(simplified.str).to eq('a')
      end

      it 'preserves repeat(0, 1) (maybe)' do
        parser = str('a').repeat(0, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.min).to eq(0)
        expect(simplified.max).to eq(1)
      end

      it 'preserves repeat(0, nil) (zero or more)' do
        parser = str('a').repeat(0)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.min).to eq(0)
        expect(simplified.max).to be_nil
      end

      it 'preserves repeat(1, nil) (one or more)' do
        parser = str('a').repeat(1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.min).to eq(1)
        expect(simplified.max).to be_nil
      end
    end

    context 'with nested repetitions' do
      it 'flattens repeat(0, 1).repeat(0, 1) to repeat(0, 1)' do
        parser = str('a').repeat(0, 1).repeat(0, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.min).to eq(0)
        expect(simplified.max).to eq(1)
        expect(simplified.parslet).to be_a(Parsanol::Atoms::Str)
      end

      it 'multiplies exact counts: repeat(2, 2).repeat(3, 3) => repeat(6, 6)' do
        parser = str('a').repeat(2, 2).repeat(3, 3)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.min).to eq(6)
        expect(simplified.max).to eq(6)
        expect(simplified.parslet).to be_a(Parsanol::Atoms::Str)
      end

      it 'multiplies exact counts: repeat(4, 4).repeat(2, 2) => repeat(8, 8)' do
        parser = str('x').repeat(4, 4).repeat(2, 2)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.min).to eq(8)
        expect(simplified.max).to eq(8)
      end

      it 'does not simplify variable repetitions' do
        parser = str('a').repeat(1, 3).repeat(2, 5)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        # Should still be nested but with simplified child
        expect(simplified).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.min).to eq(2)
        expect(simplified.max).to eq(5)
        expect(simplified.parslet).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.parslet.min).to eq(1)
        expect(simplified.parslet.max).to eq(3)
      end
    end

    context 'with sequences' do
      it 'simplifies repetitions within sequences' do
        parser = str('a').repeat(1, 1) >> str('b') >> str('c').repeat(1, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Sequence)
        expect(simplified.parslets.size).to eq(3)
        expect(simplified.parslets[0]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.parslets[0].str).to eq('a')
        expect(simplified.parslets[1]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.parslets[1].str).to eq('b')
        expect(simplified.parslets[2]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.parslets[2].str).to eq('c')
      end

      it 'preserves sequences with non-trivial repetitions' do
        parser = str('a').repeat(0, 1) >> str('b').repeat(1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Sequence)
        expect(simplified.parslets.size).to eq(2)
        expect(simplified.parslets[0]).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.parslets[1]).to be_a(Parsanol::Atoms::Repetition)
      end

      it 'handles mixed simplifiable and non-simplifiable repetitions' do
        parser = str('a').repeat(1, 1) >> str('b').repeat(0, 1) >> str('c')
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Sequence)
        expect(simplified.parslets.size).to eq(3)
        expect(simplified.parslets[0]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.parslets[1]).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.parslets[2]).to be_a(Parsanol::Atoms::Str)
      end
    end

    context 'with alternatives' do
      it 'simplifies repetitions within alternatives' do
        parser = str('a').repeat(1, 1) | str('b').repeat(1, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Alternative)
        expect(simplified.alternatives.size).to eq(2)
        expect(simplified.alternatives[0]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.alternatives[0].str).to eq('a')
        expect(simplified.alternatives[1]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.alternatives[1].str).to eq('b')
      end

      it 'handles mixed cases in alternatives' do
        parser = str('a').repeat(1, 1) | str('b').repeat(0, 1) | str('c')
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Alternative)
        expect(simplified.alternatives.size).to eq(3)
        expect(simplified.alternatives[0]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.alternatives[1]).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.alternatives[2]).to be_a(Parsanol::Atoms::Str)
      end
    end

    context 'with lookaheads' do
      it 'simplifies repetitions within positive lookahead' do
        parser = str('a').repeat(1, 1).present?
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Lookahead)
        expect(simplified.bound_parslet).to be_a(Parsanol::Atoms::Str)
        expect(simplified.positive).to be true
      end

      it 'simplifies repetitions within negative lookahead' do
        parser = str('a').repeat(1, 1).absent?
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Lookahead)
        expect(simplified.bound_parslet).to be_a(Parsanol::Atoms::Str)
        expect(simplified.positive).to be false
      end
    end

    context 'with named parslets' do
      it 'simplifies repetitions within named parslets' do
        parser = str('a').repeat(1, 1).as(:foo)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Named)
        expect(simplified.name).to eq(:foo)
        expect(simplified.parslet).to be_a(Parsanol::Atoms::Str)
        expect(simplified.parslet.str).to eq('a')
      end
    end

    context 'with complex nested structures' do
      it 'simplifies deeply nested repetitions' do
        # ((a.repeat(1,1)).repeat(1,1)).repeat(1,1)
        parser = str('a').repeat(1, 1).repeat(1, 1).repeat(1, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Str)
        expect(simplified.str).to eq('a')
      end

      it 'simplifies complex sequences with multiple repetitions' do
        # (a.repeat(1,1) >> b.repeat(2,2).repeat(3,3) >> c.repeat(0,1))
        parser = str('a').repeat(1, 1) >>
                 str('b').repeat(2, 2).repeat(3, 3) >>
                 str('c').repeat(0, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Sequence)
        expect(simplified.parslets.size).to eq(3)

        # First element: unwrapped 'a'
        expect(simplified.parslets[0]).to be_a(Parsanol::Atoms::Str)
        expect(simplified.parslets[0].str).to eq('a')

        # Second element: flattened to repeat(6, 6)
        expect(simplified.parslets[1]).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.parslets[1].min).to eq(6)
        expect(simplified.parslets[1].max).to eq(6)
        expect(simplified.parslets[1].parslet).to be_a(Parsanol::Atoms::Str)

        # Third element: preserved maybe
        expect(simplified.parslets[2]).to be_a(Parsanol::Atoms::Repetition)
        expect(simplified.parslets[2].min).to eq(0)
        expect(simplified.parslets[2].max).to eq(1)
      end

      it 'handles sequences within alternatives with repetitions' do
        parser = (str('a').repeat(1, 1) >> str('b')) |
                 (str('c').repeat(1, 1) >> str('d'))
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to be_a(Parsanol::Atoms::Alternative)
        expect(simplified.alternatives.size).to eq(2)

        # First alternative: sequence with 'a' and 'b'
        alt1 = simplified.alternatives[0]
        expect(alt1).to be_a(Parsanol::Atoms::Sequence)
        expect(alt1.parslets[0]).to be_a(Parsanol::Atoms::Str)
        expect(alt1.parslets[0].str).to eq('a')

        # Second alternative: sequence with 'c' and 'd'
        alt2 = simplified.alternatives[1]
        expect(alt2).to be_a(Parsanol::Atoms::Sequence)
        expect(alt2.parslets[0]).to be_a(Parsanol::Atoms::Str)
        expect(alt2.parslets[0].str).to eq('c')
      end
    end

    context 'with leaf nodes' do
      it 'leaves Str atoms unchanged' do
        parser = str('hello')
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to equal(parser)
      end

      it 'leaves Re atoms unchanged' do
        parser = match['a-z']
        simplified = Parsanol::Optimizer.simplify_quantifiers(parser)

        expect(simplified).to equal(parser)
      end
    end

    context 'semantic preservation' do
      it 'produces equivalent parse results for unwrapped repeat(1,1)' do
        original = str('test').repeat(1, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(original)

        input = 'test'
        expect(original.parse(input)).to eq(simplified.parse(input))
      end

      it 'produces equivalent parse results for flattened maybe.maybe' do
        original = str('x').repeat(0, 1).repeat(0, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(original)

        # Test with match
        expect(original.parse('x')).to eq(simplified.parse('x'))
        # Test without match
        expect(original.parse('')).to eq(simplified.parse(''))
      end

      it 'produces equivalent parse results for multiplied exact counts' do
        original = str('a').repeat(2, 2).repeat(3, 3)
        simplified = Parsanol::Optimizer.simplify_quantifiers(original)

        input = 'aaaaaa'
        expect(original.parse(input)).to eq(simplified.parse(input))
      end

      it 'produces equivalent parse results for complex sequences' do
        original = str('a').repeat(1, 1) >> str('b') >> str('c').repeat(0, 1)
        simplified = Parsanol::Optimizer.simplify_quantifiers(original)

        # Test with optional 'c'
        expect(original.parse('abc')).to eq(simplified.parse('abc'))
        # Test without optional 'c'
        expect(original.parse('ab')).to eq(simplified.parse('ab'))
      end
    end
  end

  describe '.simplify_sequences' do
    context 'string merging' do
      it 'merges adjacent str atoms' do
        # str('a') >> str('b') >> str('c') => str('abc')
        sequence = str('a') >> str('b') >> str('c')
        result = Parsanol::Optimizer.simplify_sequences(sequence)

        expect(result).to be_a(Parsanol::Atoms::Str)
        expect(result.str).to eq('abc')
      end

      it 'merges only adjacent strings' do
        # str('a') >> str('b') >> match['x'] >> str('c') >> str('d')
        # => str('ab') >> match['x'] >> str('cd')
        sequence = str('a') >> str('b') >> match['x'] >> str('c') >> str('d')
        result = Parsanol::Optimizer.simplify_sequences(sequence)

        expect(result).to be_a(Parsanol::Atoms::Sequence)
        expect(result.parslets.size).to eq(3)
        expect(result.parslets[0].str).to eq('ab')
        expect(result.parslets[1]).to be_a(Parsanol::Atoms::Re)
        expect(result.parslets[2].str).to eq('cd')
      end

      it 'handles empty strings' do
        sequence = str('a') >> str('') >> str('b')
        result = Parsanol::Optimizer.simplify_sequences(sequence)

        expect(result).to be_a(Parsanol::Atoms::Str)
        expect(result.str).to eq('ab')
      end
    end

    context 'sequence flattening' do
      it 'flattens nested sequences' do
        # (str('a') >> str('b')) >> (str('c') >> str('d'))
        # => str('abcd')
        inner1 = str('a') >> str('b')
        inner2 = str('c') >> str('d')
        nested = inner1 >> inner2
        result = Parsanol::Optimizer.simplify_sequences(nested)

        expect(result).to be_a(Parsanol::Atoms::Str)
        expect(result.str).to eq('abcd')
      end

      it 'flattens deeply nested sequences' do
        # ((str('a') >> str('b')) >> str('c')) >> str('d')
        # => str('abcd')
        nested = ((str('a') >> str('b')) >> str('c')) >> str('d')
        result = Parsanol::Optimizer.simplify_sequences(nested)

        expect(result).to be_a(Parsanol::Atoms::Str)
        expect(result.str).to eq('abcd')
      end
    end

    context 'sequence unwrapping' do
      it 'unwraps single-element sequences' do
        # str('a') >> (nothing else) => str('a')
        sequence = Parsanol::Atoms::Sequence.new(str('a'))
        result = Parsanol::Optimizer.simplify_sequences(sequence)

        expect(result).to be_a(Parsanol::Atoms::Str)
        expect(result.str).to eq('a')
      end
    end

    context 'recursive simplification' do
      it 'simplifies sequences in alternatives' do
        # (str('a') >> str('b')) | (str('c') >> str('d'))
        # => str('ab') | str('cd')
        alt = (str('a') >> str('b')) | (str('c') >> str('d'))
        result = Parsanol::Optimizer.simplify_sequences(alt)

        expect(result).to be_a(Parsanol::Atoms::Alternative)
        expect(result.alternatives[0]).to be_a(Parsanol::Atoms::Str)
        expect(result.alternatives[0].str).to eq('ab')
        expect(result.alternatives[1]).to be_a(Parsanol::Atoms::Str)
        expect(result.alternatives[1].str).to eq('cd')
      end

      it 'simplifies sequences in repetitions' do
        # (str('a') >> str('b')).repeat(2, 2)
        # => str('ab').repeat(2, 2)
        rep = (str('a') >> str('b')).repeat(2, 2)
        result = Parsanol::Optimizer.simplify_sequences(rep)

        expect(result).to be_a(Parsanol::Atoms::Repetition)
        expect(result.parslet).to be_a(Parsanol::Atoms::Str)
        expect(result.parslet.str).to eq('ab')
      end

      it 'simplifies sequences in lookaheads' do
        # (str('a') >> str('b')).present?
        # => str('ab').present?
        la = (str('a') >> str('b')).present?
        result = Parsanol::Optimizer.simplify_sequences(la)

        expect(result).to be_a(Parsanol::Atoms::Lookahead)
        expect(result.bound_parslet).to be_a(Parsanol::Atoms::Str)
        expect(result.bound_parslet.str).to eq('ab')
      end

      it 'simplifies sequences in named parslets' do
        # (str('a') >> str('b')).as(:test)
        # => str('ab').as(:test)
        named = (str('a') >> str('b')).as(:test)
        result = Parsanol::Optimizer.simplify_sequences(named)

        expect(result).to be_a(Parsanol::Atoms::Named)
        expect(result.parslet).to be_a(Parsanol::Atoms::Str)
        expect(result.parslet.str).to eq('ab')
      end
    end

    context 'semantic preservation' do
      it 'produces same parse results after optimization' do
        # Test that optimization doesn't change semantics
        original = str('h') >> str('e') >> str('l') >> str('l') >> str('o')
        optimized = Parsanol::Optimizer.simplify_sequences(original)

        input = 'hello'
        expect(original.parse(input)).to eq(optimized.parse(input))
      end

      it 'preserves parsing with non-string elements' do
        original = str('a') >> match['0-9'] >> str('b')
        optimized = Parsanol::Optimizer.simplify_sequences(original)

        input = 'a5b'
        expect(original.parse(input)).to eq(optimized.parse(input))
      end
    end

    context 'edge cases' do
      it 'handles sequences with only non-string elements' do
        sequence = match['a'] >> match['b'] >> match['c']
        result = Parsanol::Optimizer.simplify_sequences(sequence)

        # Should remain unchanged
        expect(result).to be_a(Parsanol::Atoms::Sequence)
        expect(result.parslets.size).to eq(3)
      end

      it 'handles empty sequences' do
        sequence = Parsanol::Atoms::Sequence.new()
        result = Parsanol::Optimizer.simplify_sequences(sequence)

        # Empty sequence stays as sequence (or could unwrap to nil)
        expect(result).to be_a(Parsanol::Atoms::Sequence)
      end

      it 'handles single string in sequence' do
        sequence = Parsanol::Atoms::Sequence.new(str('test'))
        result = Parsanol::Optimizer.simplify_sequences(sequence)

        expect(result).to be_a(Parsanol::Atoms::Str)
        expect(result.str).to eq('test')
      end
    end
  end
end
