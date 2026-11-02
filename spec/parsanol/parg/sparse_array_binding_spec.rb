# frozen_string_literal: true

require "parsanol"
require "json"

# Binding-harvest guards: the pairing semantics, the phantom contract,
# the loud-loss check and the (text) span type — parsanol-ruby
# #381/#408/#412/#413/#382.
RSpec.describe "sparse array-binding pairing" do
  # parsanol-ruby#412/#408: the repetition-root fallback that gave this
  # grammar per-instance pairing claimed every repetition-root array as
  # instances — for per-token shapes it split paired captures into
  # single-field rows and sprouted phantom {} rows (the pubid iec/csa
  # breaks). Claiming a bare top array is magic, so it is gone and a
  # repetition-root shape pairs by occurrence — the long-standing
  # baseline the fleet's 1.3.114 outputs were built on. The keyed
  # instance path (the shape nesting the group's instances under the
  # prefix key) keeps per-instance pairing; the DECLARATIVE instance
  # mapping (bind assertions, parsanol-ruby#414) is its successor.
  def sparse_artifact
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

  it "pairs a dense capture by occurrence" do
    bound = sparse_artifact.parse_and_bind("identifier", "ABC:23")
    expect(bound).to eq(csa_code_part: [{ part_code: "ABC", part_series: "23" }])
  end

  it "pairs a repetition-root shape by occurrence" do
    bound = sparse_artifact.parse_and_bind("identifier", "ABC DEF:23")
    expect(bound).to eq(
      csa_code_part: [
        { part_code: "ABC", part_series: "23" },
        { part_code: "DEF" },
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

  describe "sibling instances of a repetition-root shape" do
    # parsanol-ruby#408/#412: a repetition-root shape pairs by occurrence
    # (the fallback that claimed the bare top array as instances is
    # gone); phantom-free rows fall out naturally, and zero firing
    # captures bind no key at all (the rs#370 absent reading).
    #
    # parsanol-ruby#417: occurrence pairing is scoped to the BINDING'S
    # OWN GROUP — the occurrence count that sizes the rows is the
    # group's captures' occurrences, never the entry's total
    # sibling-row count, and a group whose captures match nothing
    # binds no key at all (no phantom slots from unrelated rows).
    def artifact
      source = <<~PARG
        grammar Sibling version "1.0.0" edition 2 {
          word = 1*( %x41-5A / %x61-7A )
          digit = 1*( %x30-39 )
          dash = "-"
          plus = "+"
          pub = ( word ) as publisher
          cop = ( plus ( word ) as copublisher )
          num = ( digit ) as number
          supp = ( dash ( word ) as supplement_code )
          item = ( pub / cop / num / supp )
          identifier = 1*( item )
          entry identifier: identifier
          bindings identifier {
            copublisher -> items[].copublisher (string)
            supplement_code -> supps[].supplement_code (string)
          }
          test {
            accept "IEC+ISO1234"
          }
        }
      PARG
      envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
      Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    end

    it "binds rows for the instances that carry the capture (#408)" do
      bound = artifact.parse_and_bind("identifier", "IEC+ISO1234")
      expect(bound).to eq(items: [{ copublisher: "ISO" }])
    end

    it "does not turn unrelated sibling rows into phantom slots (#417)" do
      # Three top-level rows (publisher, copublisher, number), one
      # copublisher occurrence: the items group binds exactly one row.
      bound = artifact.parse_and_bind("identifier", "IEC+ISO1234")
      rows = bound[:items] || bound["items"]
      expect(rows.length).to eq(1)
    end

    it "binds no key for a group whose captures match nothing (#417)" do
      # No dash in the input: supplement_code has zero occurrences, so
      # the supps group is absent entirely — not [{}], not [].
      bound = artifact.parse_and_bind("identifier", "IEC+ISO1234")
      expect(bound).not_to have_key(:supps)
      expect(bound).not_to have_key("supps")
    end

    it "pairs each group independently when both fire (#417)" do
      bound = artifact.parse_and_bind("identifier", "IEC+ISO12-AX")
      expect(bound).to eq(
        items: [{ copublisher: "ISO" }],
        supps: [{ supplement_code: "AX" }],
      )
    end

    it "binds no key when no instance carries the capture (#408)" do
      bound = artifact.parse_and_bind("identifier", "IEC1234")
      expect(bound).to eq({})
    end
  end

  describe "the phantom row contract (#408)" do
    # Where instances are identified (keyed under the prefix), every
    # instance materializes a row; an instance that binds none of the
    # group is the contracted {} phantom — never nil, never dropped.
    def artifact
      source = <<~PARG
        grammar Phantom version "1.0.0" edition 2 {
          word = 1*( %x41-5A / %x61-7A )
          digit = 1*( %x30-39 )
          base = ( word ) as code
          other = ( digit ) as other_code
          item = ( base / other )
          identifier = ( ( 1*( item ) ) as items )
          entry identifier: identifier
          bindings identifier {
            code -> items[].code (string)
          }
        }
      PARG
      envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
      Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    end

    it "materializes {} rows for instances that bind nothing" do
      bound = artifact.parse_and_bind("identifier", "A1B")
      expect(bound).to eq(
        items: [{ code: "A" }, {}, { code: "B" }],
      )
    end
  end

  describe "the loud-loss check (#413)" do
    # A declared capture that the TREE carries but the bound map
    # receives nowhere is silent data loss — bind time raises BindError
    # naming the capture. In-language the path validator already
    # forbids scoping a binding where the grammar never nests the
    # capture, so this invariant is unit-tested directly on
    # Bindings.apply with a crafted entry: `marker` fires at the top
    # level while its binding targets the keyed items[] group, whose
    # instances never carry it. Absence from the tree is legitimate
    # optionality and never raises.
    def artifact
      source = <<~PARG
        grammar Lossy version "1.0.0" edition 2 {
          word = 1*( %x41-5A / %x61-7A )
          marker = ( "!" ) as marker
          base = ( word ) as code
          identifier = [ ( marker ) ] ( ( 1*( base ) ) as items )
          entry identifier: identifier
          bindings identifier {
            code -> items[].code (string)
          }
        }
      PARG
      envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
      Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    end

    it "raises BindError naming the tree-present capture that binds nowhere" do
      shape = artifact.parse("identifier", "!ABC")
      entry = {
        "name" => "identifier",
        "bindings" => [
          { "capture" => "marker", "path" => "items[].marker", "type" => "string",
            "card" => nil, "preprocess" => nil },
        ],
      }
      expect { Parsanol::PARG::Bindings.apply(artifact, entry, shape) }
        .to raise_error(Parsanol::PARG::BindError, /marker.*present in the parse tree/m)
    end

    it "does not raise when the capture is absent from the tree" do
      shape = artifact.parse("identifier", "ABC")
      expect(artifact.apply_bindings("identifier", shape))
        .to eq(items: [{ code: "ABC" }])
    end
  end

  describe "the (text) binding type (#382)" do
    # A capture whose body carries inner captures binds a hash of them;
    # (text) delivers the matched span as one String while the inner
    # captures still fire as their own bindings — no (any)-normalize
    # shim needed.
    def artifact
      source = <<~PARG
        grammar TextSpan version "1.0.0" edition 2 {
          word = 1*( %x41-5A / %x61-7A )
          dash = "-"
          code = ( word ) as code_word
          vap = ( ( code ) *( dash ( code ) ) ) as vap_span
          item = ( vap )
          identifier = 1*( item )
          entry identifier: identifier
          bindings identifier {
            code_word -> parts[].code_word (string)
            vap_span -> vap[].vap_span (text)
          }
        }
      PARG
      envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
      Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    end

    it "binds the matched span as text beside the inner captures" do
      bound = artifact.parse_and_bind("identifier", "ABC-DEF-GHI")
      expect(bound).to eq(
        parts: [{ code_word: "ABC" }, { code_word: "DEF" }, { code_word: "GHI" }],
        vap: [{ vap_span: "ABC-DEF-GHI" }],
      )
    end
  end
end
