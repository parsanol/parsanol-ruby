# frozen_string_literal: true

require "spec_helper"

# A dispatched alternative branch that matched must not fall through into
# the next branch's code. The lead-byte tables are disjoint, but the input
# AFTER the branch's match can still satisfy a later branch's terminals:
# pubid's ieee `prefix = space? ('/' / '-' / space)` on " - Redline"
# dispatched the '-' branch, matched "-", then executed the ' ' branch's
# STR on the byte after the dash — the prefix consumed " - " and the parse
# drifted three bytes off (GH-regression surfaced as the relaton
# downstream legs' "IEEE Std 1012-1998 - Redline" → "1012/DRedline").
RSpec.describe "VM byte-dispatch branch termination" do
  def build_ident
    alnum = Parsanol::Atoms::Re.new("[0-9A-Za-z]")
    dash = Parsanol::Atoms::Str.new("-")
    space = Parsanol::Atoms::Str.new(" ")
    v_cap = Parsanol::Atoms::Named.new(
      Parsanol::Atoms::Sequence.new(dash.maybe, alnum.repeat(1)), :draft_version
    )
    prefix = Parsanol::Atoms::Sequence.new(
      space.maybe, Parsanol::Atoms::Alternative.new(Parsanol::Atoms::Str.new("/"), dash, space)
    )
    draft = Parsanol::Atoms::Named.new(
      Parsanol::Atoms::Sequence.new(prefix, v_cap.maybe), :draft
    )
    number = alnum.repeat(1).as(:number)
    redline = Parsanol::Atoms::Named.new(
      Parsanol::Atoms::Sequence.new(space, (dash >> space).maybe,
                                    Parsanol::Atoms::Str.new("Redline")), :redline
    )
    Parsanol::Atoms::Sequence.new(number, draft.maybe, redline.maybe)
  end

  it "matches the tree interpreter on a dispatched branch followed by its sibling's lead byte" do
    ident = build_ident
    input = "1012 - Redline"

    source = Parsanol::Source.new(input)
    success, value = ident.run_with_context(source, nil, true)
    expect(success).to be(true)

    expect(ident.parse(input)).to eq(ident.finalize_result(value))
  end

  it "does not consume a sibling branch's terminal after the dispatched match" do
    ident = build_ident

    # The '-' branch matches "-" alone; the ' ' that follows belongs to
    # the redline clause, not to the prefix. The drift rendered as
    # draft_version "Redline" (prefix " - ").
    result = ident.parse("1012 - Redline")
    expect(result).to eq(
      number: Parsanol::Slice.new(0, "1012", nil),
      draft: Parsanol::Slice.new(4, " -", nil),
      redline: Parsanol::Slice.new(6, " Redline", nil),
    )
  end

  it "keeps every dispatch branch's fall-through isolated" do
    parser = Class.new(Parsanol::Parser) do
      rule(:sep) { str("/") | str("-") | str(" ") }
      rule(:bracket) { (str("[") >> sep.as(:sep) >> str("]")).as(:bracket) }
      rule(:word) { match("[a-z]").repeat(1).as(:word) }
      rule(:item) { bracket | word }
      rule(:list) { item.repeat(1) }
      root(:list)
    end.new

    # Each dispatched sep branch must consume exactly one byte: the byte
    # after the match belongs to the next item, not to a fallen-through
    # sibling branch.
    expect(parser.parse("x[-]y", mode: :ruby)).to eq(
      [{ word: Parsanol::Slice.new(0, "x", nil) },
       { bracket: { sep: Parsanol::Slice.new(2, "-", nil) } },
       { word: Parsanol::Slice.new(4, "y", nil) }],
    )
    expect(parser.parse("x[ ]y", mode: :ruby)).to eq(
      [{ word: Parsanol::Slice.new(0, "x", nil) },
       { bracket: { sep: Parsanol::Slice.new(2, " ", nil) } },
       { word: Parsanol::Slice.new(4, "y", nil) }],
    )
  end

  it "compiles dispatched alternatives with branch-exit jumps" do
    ident = build_ident
    program = Parsanol::VM.program_for(ident)
    expect(program).not_to be_nil

    # The program is a flat stream of 4-slot instructions: opcode at
    # pc, operands at pc+1..pc+3. Find the BYTE_DISPATCH instruction and
    # assert the non-last branch bodies end in a JMP — the terminator
    # that prevents fall-through.
    _ = 0
    operand = 1
    str_op = 1
    jmp_op = 8
    dispatch_op = 27
    seq_end_op = 5
    dispatch_idx = (0...program.size).step(4).find do |pc|
      program[pc] == dispatch_op
    end
    expect(dispatch_idx).not_to be_nil

    table = program[dispatch_idx + operand]
    dash_target = table["-".ord]
    space_target = table[" ".ord]
    slash_target = table["/".ord]
    expect([dash_target, space_target, slash_target]).to all(be_positive)
    # Branch bodies are single STR instructions; the non-last ones are
    # followed by their exit JMP. The LAST branch falls through into the
    # continuation, which is exactly where the JMPs land.
    continuation = space_target + 4
    expect(program[slash_target]).to eq(str_op)
    expect(program[slash_target + 4]).to eq(jmp_op)
    expect(program[dash_target]).to eq(str_op)
    expect(program[dash_target + 4]).to eq(jmp_op)
    expect(program[space_target]).to eq(str_op)
    expect(program[continuation]).to eq(seq_end_op)
  end
end
