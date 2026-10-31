# frozen_string_literal: true

require "parsanol"
require "json"

# parsanol-ruby#381: array bindings pair capture occurrences to group
# instances BY OCCURRENCE INDEX — a sparse capture (firing in only
# some instances) landed on the wrong instance. Pairing is now
# positional: each instance's subtree owns its captures.
RSpec.describe "sparse array-binding pairing" do
  def artifact
    source = <<~PARG
      grammar Sparse version "1.0.0" edition 2 {
        word = 1*( %x41-5A / %x61-7A )
        colon = ":"
        digit = %x30-39
        part = ( word ) as part_code
        trailing = ( colon ( 1*( digit ) ) as part_series )
        csa_code_part = ( part ) trailing_part
        trailing_part = ( trailing ) / ( space_end )
        space_end = ( " " )
        identifier = 1*( csa_code_part )
        entry identifier: identifier
        bindings identifier {
          part_code -> csa_code_part[].part_code (string)
          part_series -> csa_code_part[].part_series (string)
        }
        test {
          accept "ABC:23"
        }
      }
    PARG
    envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
    Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
  end

  it "pairs a dense capture by instance" do
    bound = artifact.parse_and_bind("identifier", "ABC:23")
    expect(bound).to eq(csa_code_part: [{ part_code: "ABC", part_series: "23" }])
  end

  it "pairs a sparse capture to its own instance (#381)" do
    bound = artifact.parse_and_bind("identifier", "ABC DEF:23")
    expect(bound).to eq(
      csa_code_part: [
        { part_code: "ABC" },
        { part_code: "DEF", part_series: "23" },
      ],
    )
  end

  it "binds nothing when the repetition fires zero instances" do
    # The tree carries `parts: []` for the zero-iteration repetition;
    # the bound map omits the key — the occurrence path's
    # `return if count.zero?` reading, which the recorded native
    # expectations (the pubid corpora) and the pubid builders rely on
    # (parsanol-rs#370).
    source = <<~PARG
      grammar ZeroRep version "1.0.0" edition 2 {
        word = 1*( %x41-5A / %x61-7A )
        space = " "
        digit = %x30-39
        part = ( ( digit ) ( word ) ) as part_code
        identifier = "X" space ( *( part space ) ) as parts ( ( word ) ) as tail

        bindings identifier {
          tail -> tail (string)
          part_code -> parts[].part_code (string)
        }

        entry identifier: identifier
        test {
          accept "X AB"
          accept "X 5AB CD"
        }
      }
    PARG
    envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
    art = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))

    tree = art.parse("identifier", "X AB")
    expect(tree).to include(parts: [])
    expect(art.parse_and_bind("identifier", "X AB")).to eq(tail: "AB")
    expect(art.parse_and_bind("identifier", "X 5AB CD")).to eq(
      tail: "CD",
      parts: [{ part_code: "5AB" }],
    )
  end
end
