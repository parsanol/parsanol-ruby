# frozen_string_literal: true

require "spec_helper"

# The VM's packed value spans are BYTE-based: STR packs the literal's byte
# length, ANY and the RUN ops pack the matched character's UTF-8 byte
# width, and materialize byteslices the stored (offset, length). The RE
# instruction alone stored the match's CHARACTER count in that slot, so
# every slice containing a multibyte character came out truncated —
# ruby#407: lutaml-path's `Class[éin]` reached consumers as
# "Class[\xC3in]" (é's second continuation byte dropped). The RE op now
# packs the byte length like every other span producer.
RSpec.describe "VM multibyte spans" do
  # Lutaml::Path-shaped grammar: a quantified negated charset, a per-char
  # negated charset repetition with absent? lookaheads — the shapes the
  # issue exercised. The inner segment excludes ']' so the bracket is
  # unambiguous (mirroring lutaml-path, whose segments are ident chars
  # and whose brackets live in the attrs rule).
  def segment_parser_class
    Class.new(Parsanol::Parser) do
      rule(:sp)        { match(/\s/).repeat }
      rule(:sp?)       { sp.maybe }
      rule(:separator) { str("::") }
      rule(:dot)       { str(".") }

      rule(:quantified_seg) { match(/[^\[\]:]+/).as(:name) }

      rule(:regular_char) do
        (separator.absent? >> dot.absent? >> str("\\").absent? >> match(/[^\]]/)) |
          (str("\\") >> str("::")) |
          (str("\\") >> str("."))
      end
      rule(:lpath_segment) { regular_char.repeat(1).as(:content) }

      rule(:document) do
        sp? >> quantified_seg >> sp? >> str("[") >> lpath_segment >> str("]") >> sp?
      end
      root(:document)
    end
  end

  [
    ["é", "pkg[é]"],
    ["ü", "pkg[ü]"],
    ["标文本", "pkg[标文本]"],
    ["🙂", "pkg[🙂]"],
    ["éü标🙂in", "pkg[éü标🙂in]"],
    ["éü标🙂", "cléü标🙂[éü标🙂]"],
  ].each do |inner, input|
    it "round-trips #{inner.inspect} through the VM byte-exactly" do
      parser = segment_parser_class.new
      result = parser.parse(input, mode: :ruby)
      content = result.fetch(:content)

      expect(content).to eq(inner)
      expect(content.to_s.valid_encoding?).to be(true)
      expect(content.to_s.bytes).to eq(inner.bytes)
    end
  end

  it "round-trips a multibyte quantified-charset match byte-exactly" do
    parser = segment_parser_class.new
    result = parser.parse("cléü标🙂[é]", mode: :ruby)

    expect(result.fetch(:name).to_s).to eq("cléü标🙂")
    expect(result.fetch(:name).to_s.bytes).to eq("cléü标🙂".bytes)
  end

  it "keeps byte-exact spans when the multibyte char is not at the start" do
    parser = segment_parser_class.new
    result = parser.parse("pkg[abéü]", mode: :ruby)

    expect(result.fetch(:content).to_s).to eq("abéü")
    # Slice offsets are byte positions: the inner segment starts after
    # "pkg[" (4 bytes).
    expect(result.fetch(:content).offset).to eq(4)
  end

  it "keeps the VM enabled for the grammar (the VM path is the one under test)" do
    parser = segment_parser_class.new
    parser.parse("pkg[éin]", mode: :ruby)

    program = Parsanol::VM.program_for(parser.root)
    expect(program).not_to be_nil
    expect(program).not_to eq(:fallback)
  end

  it "matches interpreter output tree-for-tree on multibyte input" do
    input = "pkg[éü标🙂in]"
    parser = segment_parser_class.new
    vm_tree = parser.parse(input, mode: :ruby)

    # The interpreter is the fallback engine: its trees must agree with
    # the VM's, or a VM-only regression would drift apart on BAIL.
    Parsanol::VM.disable_for!(parser.root)
    interpreter_tree = parser.parse(input, mode: :ruby)

    expect(vm_tree).to eq(interpreter_tree)
  end
end
