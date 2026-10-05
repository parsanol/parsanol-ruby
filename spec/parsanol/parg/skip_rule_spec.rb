# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#134: grammar-declared skip rule (trivia injection).
RSpec.describe "PARG skip rule" do
  def compile_parg(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  def parse_artifact(envelope, input)
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    artifact.parse("document", input, mode: :ruby)
  end

  it "injects trivia between tokens: tail comments after code" do
    envelope = compile_parg(<<~PARG)
      grammar Skippy version "1" {
        skip = line_comment
        line_comment = "//" ( *( !"\\n" ANY ) ) [ "\\n" ]
        pair = ( word " " word ) as pair
        word = ( 1*( ALPHA ) )
        entry document: pair
        test { accept "left right" }
      }
    PARG
    tree = parse_artifact(envelope, "left // trailing note\nright")
    # trivia stays OUT of the capture: the pair value is the two words
    expect(tree[:pair].to_s).to eq("left right")
  end

  it "consumes leading, inter-token and tail trivia" do
    envelope = compile_parg(<<~PARG)
      grammar Skippy version "1" {
        skip = spaces
        spaces = 1*" "
        pair = ( "a" "b" ) as pair
        entry document: pair
        test { accept "ab" }
      }
    PARG
    tree = parse_artifact(envelope, "  ab  ")
    # v1 semantics: trivia between captures and at entry boundaries;
    # inside a captured span the grammar models trivia explicitly
    expect(tree[:pair].to_s).to eq("ab")
  end

  it "keeps trivia capture-free" do
    envelope = compile_parg(<<~PARG)
      grammar Skippy version "1" {
        skip = spaces
        spaces = 1*" "
        text = ( 1*( ALPHA ) ) as text
        entry document: text
        test { accept "  abc" }
      }
    PARG
    tree = parse_artifact(envelope, "  abc")
    expect(tree.keys).to eq([:text])
    expect(tree[:text].to_s).to eq("abc")
  end

  it "preserves ordered-choice and backtracking across injected skips" do
    envelope = compile_parg(<<~PARG)
      grammar Skippy version "1" {
        skip = spaces
        spaces = 1*" "
        pick = ( ( "ab" / "a" ) ) as pick
        entry document: pick
        test { accept "a" }
        test { accept " ab" }
      }
    PARG
    expect(parse_artifact(envelope, "a")[:pick].to_s).to eq("a")
    expect(parse_artifact(envelope, " ab")[:pick].to_s).to eq("ab")
  end

  it "rejects a nullable skip rule at compile time" do
    expect do
      compile_parg(<<~PARG)
        grammar Bad version "1" {
          skip = maybe
          maybe = [ "x" ]
          word = 1*( ALPHA )
          entry document: word
        }
      PARG
    end.to raise_error(Parsanol::PARG::CompileError, /non-nullable/)
  end

  it "reserves skip: rules may not be named or referenced as skip" do
    expect do
      compile_parg(<<~PARG)
        grammar Bad version "1" {
          skip = "x"
          word = skip
          entry document: word
        }
      PARG
    end.to raise_error(Parsanol::PARG::ParseError)
  end

  # parsanol-ruby#140 (rs#172 expressir note): trivia may recurse. The
  # skip-exemption closure must walk repetitions/optionals/predicates, or
  # the injection re-enters the trivia rule's own body at the same
  # position — accidental left recursion, stack exhaustion.
  describe "recursive trivia" do
    def compile_nested
      compile_parg(<<~PARG)
        grammar Nested version "1" {
          skip = trivia
          trivia = 1*( ( 1*" " ) / comment )
          comment = "(*" *( comment / ( !"*)" ANY ) ) "*)"
          word = ( 1*( ALPHA ) )
          entry document: word
        }
      PARG
    end

    it "parses nested block comments in trivia" do
      expect(parse_artifact(compile_nested, "(* outer (* inner *) tail *) abc").to_s)
        .to eq("abc")
    end

    it "parses three-level nesting without exhausting the stack" do
      expect(parse_artifact(compile_nested, "(* a (* b (* c *) d *) e *) abc").to_s)
        .to eq("abc")
    end

    it "bridges multi-unit trivia gaps (space + comment + space)" do
      expect(parse_artifact(compile_nested, "(*x*) abc (*y (*z*) w*)").to_s)
        .to eq("abc")
    end

    it "accepts plain trivia unchanged" do
      expect(parse_artifact(compile_nested, "(* note *) abc").to_s).to eq("abc")
    end
  end

  it "records the declaration in the envelope; non-skip envelopes unchanged" do
    with_skip = compile_parg(<<~PARG)
      grammar S version "1" {
        skip = spaces
        spaces = 1*" "
        word = 1*( ALPHA )
        entry document: word
      }
    PARG
    without_skip = compile_parg(<<~PARG)
      grammar S version "1" {
        word = 1*( ALPHA )
        entry document: word
      }
    PARG
    expect(with_skip["skip"]).to eq("spaces")
    expect(without_skip).not_to have_key("skip")
  end

  describe "QoL companions" do
    it "materializes character-class shorthands" do
      envelope = compile_parg(<<~PARG)
        grammar QoL version "1" {
          code = 3*( DIGIT ) "-" 2*( HEXDIG )
          entry document: code
          test { accept "123-AB" }
        }
      PARG
      expect(parse_artifact(envelope, "123-AB").to_s).to eq("123-AB")
    end

    it "provides the any-until operator" do
      envelope = compile_parg(<<~PARG)
        grammar QoL version "1" {
          note = until "//"
          entry document: note
          test { accept "hello there" }
        }
      PARG
      expect(parse_artifact(envelope, "hello there").to_s).to eq("hello there")
    end
  end

  describe "atomic rules" do
    def token_envelope(atomic)
      word_decl = atomic ? "atomic word = ( 1*( ALPHA ) )" : "word = ( 1*( ALPHA ) )"
      compile_parg(<<~PARG)
        grammar Tok version "1" {
          skip = spaces
          spaces = 1*" "
          #{word_decl}
          sep = ","
          item = ( word ) as item
          list = ( item *( sep item ) ) as list
          entry document: list
        }
      PARG
    end

    it "keeps token rules contiguous: trivia does not span them" do
      envelope = token_envelope(true)
      tree = parse_artifact(envelope, "foo, bar")
      items = tree[:list].is_a?(Hash) ? [tree[:list][:item]] : tree[:list].map { |e| e[:item] }
      expect(items.map(&:to_s)).to eq(%w[foo bar])
      expect(items.map(&:offset)).to eq([0, 5])

      expect { parse_artifact(envelope, "foo bar") }
        .to raise_error(Parsanol::ParseFailed)
    end

    it "non-atomic runs still span trivia between iterations (contrast)" do
      envelope = token_envelope(false)
      tree = parse_artifact(envelope, "foo bar")
      expect(tree[:list][:item].to_s).to eq("foobar")
    end

    it "reserves atomic as a keyword" do
      expect do
        compile_parg(<<~PARG)
          grammar Bad version "1" {
            atomic = "x"
            entry document: atomic
          }
        PARG
      end.to raise_error(Parsanol::PARG::ParseError)
    end
  end
end
