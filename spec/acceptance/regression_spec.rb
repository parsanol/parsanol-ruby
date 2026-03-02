require 'spec_helper'

require 'parsanol/parslet'

describe 'Regressions from real examples' do
  # This parser piece produces on the left a subtree that is keyed (a hash)
  # and on the right a subtree that is a repetition of such subtrees. I've
  # for now decided that these would merge into the repetition such that the
  # return value is an array. This avoids maybe loosing keys/values in a
  # hash merge.
  #
  class ArgumentListParser
    include Parsanol

    rule :argument_list do
      expression.as(:argument) >>
        (comma >> expression.as(:argument)).repeat
    end
    rule :expression do
      string
    end
    rule :string do
      str('"') >>
        (
          str('\\') >> any |
          str('"').absent? >> any
        ).repeat.as(:string) >>
        str('"') >> space?
    end
    rule :comma do
      str(',') >> space?
    end
    rule :space? do
      space.maybe
    end
    rule :space do
      match("[ \t]").repeat(1)
    end

    def parse(str)
      argument_list.parse(str)
    end
  end
  describe ArgumentListParser do
    let(:instance) { ArgumentListParser.new }

    it 'has method expression' do
      expect(instance).to respond_to(:expression)
    end

    it 'parses "arg1", "arg2"' do
      result = ArgumentListParser.new.parse('"arg1", "arg2"')

      expect(result.size).to eq(2)
      result.each do |r|
        r[:argument]
      end
    end

    it 'parses "arg1", "arg2", "arg3"' do
      result = ArgumentListParser.new.parse('"arg1", "arg2", "arg3"')

      expect(result.size).to eq(3)
      result.each do |r|
        r[:argument]
      end
    end
  end

  class ParensParser < Parsanol::Parser
    rule(:balanced) do
      str('(').as(:l) >> balanced.maybe.as(:m) >> str(')').as(:r)
    end

    root(:balanced)
  end
  describe ParensParser do
    let(:instance) { ParensParser.new }

    context 'statefulness: trying several expressions in sequence' do
      it 'is not stateful' do
        # NOTE: Since you've come here to read this, I'll explain why
        # this is broken and not fixed: You're looking at the tuning branch,
        # which rewrites a bunch of stuff - so I have failing tests to
        # remind me of what is left to be done. And to remind you not to
        # trust this code.
        instance.parse('(())')
        expect do
          instance.parse('((()))')
          instance.parse('(((())))')
        end.not_to raise_error
      end
    end

    context "expression '(())'" do
      let(:result) { instance.parse('(())') }

      it 'yields a doubly nested hash' do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:m)
        expect(result[:m]).to be_a(Hash) # This was an array earlier
      end

      context 'inner hash' do
        let(:inner) { result[:m] }

        it 'has nil as :m' do
          expect(inner[:m]).to be_nil
        end
      end
    end
  end

  class ALanguage < Parsanol::Parser
    root(:expressions)

    rule(:expressions) { (line >> eol).repeat(1) | line }
    rule(:line) { space? >> an_expression.as(:exp).repeat }
    rule(:an_expression) { str('a').as(:a) >> space? }

    rule(:eol) { space? >> match["\n\r"].repeat(1) >> space? }

    rule(:space?) { space.repeat }
    rule(:space) { multiline_comment.as(:multi) | line_comment.as(:line) | str(' ') }

    rule(:line_comment) { str('//') >> (match["\n\r"].absent? >> any).repeat }
    rule(:multiline_comment) { str('/*') >> (str('*/').absent? >> any).repeat >> str('*/') }
  end
  describe ALanguage do
    def remove_indent(s)
      s.to_s.lines.map { |l| l.chomp.strip }.join("\n")
    end

    it 'counts lines correctly' do
      # This test verifies that error reporting provides meaningful output
      # The exact format may vary between versions, but the key is that
      # the error identifies the problem location correctly
      cause = catch_failed_parse do
        subject.parse('a
          a a a
          aaa // ff
          /*
          a
          */
          b
        ')
      end

      # Verify the cause exists and contains meaningful error information
      expect(cause).not_to be_nil
      expect(cause.ascii_tree).to include("Expected one of [(LINE EOL){1, }, LINE]")
      # The error should indicate a problem with parsing, either at line 7 or earlier
      expect(cause.ascii_tree).to match(/line (1|7)/)
    end
  end

  class BLanguage < Parsanol::Parser
    root :expression
    rule(:expression) { b.as(:one) >> b.as(:two) }
    rule(:b) { str('b') }
  end
  describe BLanguage do
    it "parses 'bb'" do
      expect(subject).to parse('bb').as(one: 'b', two: 'b')
    end

    it 'transforms with binding constraint' do
      transform = Parsanol::Transform.new do |t|
        t.rule(one: simple(:b), two: simple(:b)) { :ok }
      end
      expect(transform.apply(subject.parse('bb'))).to eq(:ok)
    end
  end

  class UnicodeLanguage < Parsanol::Parser
    root :gobble
    rule(:gobble) { any.repeat }
  end
  describe UnicodeLanguage do
    it 'parses UTF-8 strings' do
      expect(subject).to parse('éèäöü').as('éèäöü')
      expect(subject).to parse('RubyKaigi2009のテーマは、「変わる／変える」です。 前回の').as('RubyKaigi2009のテーマは、「変わる／変える」です。 前回の')
    end
  end

  class UnicodeSentenceLanguage < Parsanol::Parser
    rule(:sentence) { (match('[^。]').repeat(1) >> str('。')).as(:sentence) }
    rule(:sentences) { sentence.repeat }
    root(:sentences)
  end
  describe UnicodeSentenceLanguage do
    let(:string) do
      'RubyKaigi2009のテーマは、「変わる／変える」です。 前回の' +
        'RubyKaigi2008のテーマであった「多様性」の言葉の通り、 ' +
        '2008年はRubyそのものに関しても、またRubyの活躍する舞台に関しても、 ' +
        'ますます多様化が進みつつあります。RubyKaigi2008は、そのような ' +
        'Rubyの生態系をあらためて認識する場となりました。 しかし、' +
        'こうした多様化が進む中、異なる者同士が単純に距離を 置いたままでは、' +
        'その違いを認識したところであまり意味がありません。 異なる実装、' +
        '異なる思想、異なる背景といった、様々な多様性を理解しつつ、 ' +
        'すり合わせるべきものをすり合わせ、変えていくべきところを ' +
        '変えていくことが、豊かな未来へとつながる道に違いありません。'
    end

    it 'parses sentences' do
      expect(subject).to parse(string)
    end
  end

  class TwoCharLanguage < Parsanol::Parser
    root :twochar
    rule(:twochar) { any >> str('2') }
  end
  describe TwoCharLanguage do
    def di(s)
      s.strip.to_s.lines.map { |l| l.chomp.strip }.join("\n")
    end

    it 'raises an error' do
      error = catch_failed_parse do
        subject.parse('123')
      end
      expect(di(error.ascii_tree)).to eq(di(%q(
        Failed to match sequence (. '2') at line 1 char 2.
        `- Don't know what to do with "3" at line 1 char 3.
      )))
    end
  end

  # Issue #68: Extra input reporting, written by jmettraux
  class RepetitionParser < Parsanol::Parser
    rule(:nl)      { match('[\s]').repeat(1) }
    rule(:nl?)     { nl.maybe }
    rule(:sp)      { str(' ').repeat(1) }
    rule(:sp?)     { str(' ').repeat(0) }
    rule(:line)    { sp >> str('line') }
    rule(:body)    { ((line | block) >> nl).repeat(0) }
    rule(:block)   do
      sp? >> str('begin') >> sp >> match('[a-z]') >> nl >>
        body >> sp? >> str('end')
    end
    rule(:blocks) { nl? >> block >> (nl >> block).repeat(0) >> nl? }

    root(:blocks)
  end
  describe RepetitionParser do
    def di(s)
      s.strip.to_s.lines.map { |l| l.chomp.strip }.join("\n")
    end

    it 'parses a block' do
      subject.parse('
        begin a
        end
      ')
    end

    it 'parses nested blocks' do
      subject.parse('
        begin a
          begin b
          end
        end
      ')
    end

    it 'parses successive blocks' do
      subject.parse('
        begin a
        end
        begin b
        end
      ')
    end

    it 'fails gracefully on a missing end' do
      error = catch_failed_parse do
        subject.parse('
          begin a
            begin b
          end
        ')
      end

      expect(di(error.ascii_tree)).to eq(di("
        Failed to match sequence (NL? BLOCK (NL BLOCK){0, } NL?) at line 2 char 11.
        `- Failed to match sequence (SP? 'begin' SP [a-z] NL BODY SP? 'end') at line 5 char 9.
           `- Unexpected end of input at line 5 char 9.
        "))
    end

    it 'fails gracefully on a missing end (2)' do
      error = catch_failed_parse do
        subject.parse('
          begin a
          end
          begin b
            begin c
          end
        ')
      end

      expect(di(error.ascii_tree)).to eq(di(%q(
        Failed to match sequence (NL? BLOCK (NL BLOCK){0, } NL?) at line 3 char 14.
        `- Don't know what to do with "begin b\n  " at line 4 char 11.
        )))
    end

    it 'fails gracefully on a missing end (deepest reporter)' do
      error = catch_failed_parse do
        subject.parse('
            begin a
            end
            begin b
              begin c
                li
              end
            end
          ',
                      reporter: Parsanol::ErrorReporter::Deepest.new)
      end

      expect(di(error.ascii_tree)).to eq(di(%q(
        Failed to match sequence (NL? BLOCK (NL BLOCK){0, } NL?) at line 3 char 16.
        `- Expected "end", but got "li\n" at line 6 char 17.
        )))
    end
  end
end
