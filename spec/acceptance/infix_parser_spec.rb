require 'spec_helper'

describe 'Infix expression parsing' do
  class InfixExpressionParser < Parsanol::Parser
    rule(:space) { match['\s'] }

    def cts(atom)
      atom >> space.repeat
    end

    def infix(*args)
      Infix.new(*args)
    end

    rule(:mul_op) { match['*/'] >> str(' ').maybe }
    rule(:add_op) { match['+-'] >> str(' ').maybe }
    rule(:digit) { match['0-9'] }
    rule(:integer) { cts digit.repeat(1) }

    rule(:expression) do
      infix_expression(integer,
                       [mul_op, 2, :left],
                       [add_op, 1, :right])
    end
  end

  let(:p) { InfixExpressionParser.new }

  describe '#integer' do
    let(:i) { p.integer }

    it 'parses integers' do
      i.should parse('1')
      i.should parse('123')
    end

    it 'consumes trailing white space' do
      i.should parse('1   ')
      i.should parse('134   ')
    end

    it "doesn't parse floats" do
      i.should_not parse('1.3')
    end
  end

  describe '#multiplication' do
    let(:m) { p.expression }

    it 'parses simple multiplication' do
      m.should parse('1*2').as(left: '1', op: '*', right: '2')
    end

    it 'parses simple multiplication with spaces' do
      m.should parse('1 * 2').as(left: '1 ', op: '* ', right: '2')
    end

    it 'parses division' do
      m.should parse('1/2')
    end
  end

  describe '#addition' do
    let(:a) { p.expression }

    it 'parses simple addition' do
      a.should parse('1+2')
    end

    it 'parses complex addition' do
      a.should parse('1+2+3-4')
    end

    it 'parses a single element' do
      a.should parse('1')
    end
  end

  describe 'mixed operations' do
    let(:mo) { p.expression }

    describe 'inspection' do
      it 'produces useful expressions' do
        p.expression.parslet.inspect.should ==
          'infix_expression(INTEGER, [MUL_OP, ADD_OP])'
      end
    end

    describe 'right associativity' do
      it 'produces trees that lean right' do
        mo.should parse('1+2+3').as(
          left: '1', op: '+', right: { left: '2', op: '+', right: '3' },
        )
      end
    end

    describe 'left associativity' do
      it 'produces trees that lean left' do
        mo.should parse('1*2*3').as(
          left: { left: '1', op: '*', right: '2' }, op: '*', right: '3',
        )
      end
    end

    describe 'error handling' do
      describe 'incomplete expression' do
        it 'produces the right error' do
          cause = catch_failed_parse do
            mo.parse('1+')
          end

          cause.ascii_tree.to_s.should == <<~ERROR
            Expected INTEGER at line 1 char 3.
            `- Failed to match sequence (DIGIT{1, } SPACE{0, }) at line 1 char 3.
               `- Expected at least 1 of DIGIT at line 1 char 3.
                  `- Unexpected end of input at line 1 char 3.
          ERROR
        end
      end

      describe 'invalid operator' do
        it 'produces the right error' do
          cause = catch_failed_parse do
            mo.parse('1%')
          end

          cause.ascii_tree.to_s.should == <<~ERROR
            Don't know what to do with "%" at line 1 char 2.
          ERROR
        end
      end
    end
  end

  describe 'providing a reducer block' do
    class InfixExpressionReducerParser < Parsanol::Parser
      rule(:top) { infix_expression(str('a'), [str('-'), 1, :right]) { |l, _o, r| { and: [l, r] } } }
    end

    it 'applies the reducer' do
      result = InfixExpressionReducerParser.new.top.parse('a-a-a')
      strip_positions(result).should == { and: ['a', { and: %w[a a] }] }
    end
  end
end
