# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#129: PARG runtime state and custom-atom bindings — the
# coradoc asks. The motivating case (the issue's block-delimiter
# example): a grammar that captures its opening delimiter and requires
# the SAME delimiter to close — inexpressible without per-parse mutable
# state, trivial with set/state.
RSpec.describe "PARG runtime state and customs (#129)" do
  def compile(src)
    document = Parsanol::PARG::Parser.new(src).parse
    envelope = Parsanol::PARG::Compiler.compile(document).envelope
    [Parsanol::PARG::Artifact.new(envelope, nil, nil), envelope]
  end

  def block_grammar(delim_rule = "3*4(dash)")
    <<~G
      grammar Blocks version "1" {
        entry block: block
        state delimiter: string
        dash = %x2D
        newline = %x0A
        letter = %x61-7A / %x20
        body_line = (1*(!(state delimiter) letter))
        block = ((set delimiter = (#{delim_rule})) newline 1*(body_line newline) (state delimiter)) as block
      }
    G
  end

  describe "the block-delimiter case" do
    it "parses a 4-dash block closed by 4 dashes" do
      art, = compile(block_grammar)
      shape = art.parse("block", "----\ncode\n----")
      expect(shape[:block].to_s).to start_with("----\ncode")
    end

    it "parses a 3-dash block closed by 3 dashes (the state is per parse)" do
      art, = compile(block_grammar)
      shape = art.parse("block", "---\nabc\n---")
      expect(shape[:block].to_s).to start_with("---\nabc")
    end

    it "rejects a mismatched closer" do
      art, = compile(block_grammar)
      expect { art.parse("block", "----\ncode\n--x") }.to raise_error(Parsanol::ParseFailed)
    end

    it "rejects a too-short opening delimiter" do
      art, = compile(block_grammar)
      expect { art.parse("block", "--\nab\n--") }.to raise_error(Parsanol::ParseFailed)
    end
  end

  describe "set" do
    it "writes a literal value readable by state" do
      art, = compile(<<~G)
        grammar T version "1" {
          entry t: t
          state m: string
          t = ((set m = "a") (state m) 1*%x61-7A) as t
        }
      G
      expect(art.parse("t", "ab")[:t].to_s).to eq("b")
    end
  end

  describe "switch" do
    it "dispatches to the arm matching the slot value" do
      art, = compile(<<~G)
        grammar T version "1" {
          entry t: t
          state mode: symbol
          q = ("[Q]" 1*%x61-7A) as q
          p = ("[P]" 1*%x61-7A) as p
          t = ((set mode = "quote") (switch mode { "quote" -> q _ -> p })) as t
        }
      G
      shape = art.parse("t", "[Q]abc")
      expect(shape[:t][:q].to_s).to eq("[Q]abc")
    end

    it "falls through to the default arm" do
      art, = compile(<<~G)
        grammar T version "1" {
          entry t: t
          state mode: symbol
          q = ("[Q]" 1*%x61-7A) as q
          p = ("[P]" 1*%x61-7A) as p
          t = ((set mode = "other") (switch mode { "quote" -> q _ -> p })) as t
        }
      G
      shape = art.parse("t", "[P]xyz")
      expect(shape[:t][:p].to_s).to eq("[P]xyz")
    end
  end

  describe "custom bindings" do
    before do
      stub_const("SpecMarkA", Class.new(Parsanol::Atoms::Custom) do
        define_method(:try_match) do |source, _context, _consume_all|
          next [false, nil] if source.peek(1) != "A"

          source.bytepos += 1
          [true, "A"]
        end
      end)
    end

    it "resolves the class and runs the atom" do
      art, envelope = compile(<<~G)
        grammar T version "1" {
          entry t: t
          custom mark_a = "SpecMarkA"
          t = ((mark_a) 1*%x61-7A) as t
        }
      G
      expect(envelope["customs"]).to eq("mark_a" => "SpecMarkA")
      expect(art.parse("t", "Abc")[:t].to_s).to eq("bc")
      expect { art.parse("t", "xbc") }.to raise_error(Parsanol::ParseFailed)
    end

    it "raises loudly when the class cannot resolve" do
      expect do
        compile(<<~G)
          grammar T version "1" {
            entry t: t
            custom mark_a = "NoSuchAtomAnywhere"
            t = ((mark_a)) as t
          }
        G
      end.to raise_error(Parsanol::PARG::CompileError, /NoSuchAtomAnywhere/)
    end
  end

  describe "envelope and engine routing" do
    it "records states, customs and the dynamic flag" do
      _, envelope = compile(<<~G)
        grammar T version "1" {
          entry t: t
          state m: string
          t = ((set m = "x") (state m)) as t
        }
      G
      expect(envelope["states"]).to eq("m" => "string")
      expect(envelope["dynamic"]).to be(true)
    end

    it "does not flag stateless grammars" do
      _, envelope = compile(<<~G)
        grammar T version "1" {
          entry t: t
          t = (1*%x61-7A) as t
        }
      G
      expect(envelope).not_to have_key("dynamic")
    end

    it "round-trips a dynamic artifact through from_json" do
      art, = compile(block_grammar)
      restored = Parsanol::PARG::Artifact.from_json(JSON.generate(art.envelope))
      shape = restored.parse("block", "----\ncode\n----")
      expect(shape[:block].to_s).to start_with("----\ncode")
    end
  end
end
