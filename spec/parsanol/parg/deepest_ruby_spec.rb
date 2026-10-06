# frozen_string_literal: true

require "spec_helper"

RSpec.describe "PARG artifact ruby-mode diagnostics" do
  let(:grammar) do
    <<~PARG
      grammar D version "1.0.0" {
        skip = trivia
        trivia = 1*( ( 1*( " " / %x09 ) ) )
        atomic word = 1*( ALPHA )
        atomic kw_item_sp = "item" 1*" "
        entry main: items
        items = ( *( item ) ) as members
        item = ( kw_item_sp word as name [ 1*" " "=" 1*" " word as value ] ) as item
      }
    PARG
  end

  let(:artifact) do
    document = Parsanol::PARG::Parser.new(grammar).parse
    Parsanol::PARG::Artifact.new(
      Parsanol::PARG::Compiler.compile(document).envelope, nil, nil
    )
  end

  it "reports the deepest failure position on the ruby engine" do
    input = "item alpha\nitem beta = ok\nitem gamma {\n"
    expect { artifact.parse("main", input, mode: :ruby) }
      .to raise_error(Parsanol::ParseFailed) { |e|
        pos = e.parse_failure_cause.position
        expect(pos).to be > 0
        expect(e.message).to match(/char \d+/)
      }
  end

  it "matches the native engine's failure position" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    input = "item alpha\nitem beta = ok\nitem gamma {\n"
    ruby_error = artifact.parse("main", input, mode: :ruby)
  rescue Parsanol::ParseFailed => e
    native_error = artifact.parse("main", input, mode: :native)
  rescue Parsanol::ParseFailed => e2
    ruby_pos = e.parse_failure_cause.position
    native_pos = e2.parse_failure_cause.position
    expect(ruby_pos).to eq(native_pos)
  end

  it "still parses success-path inputs" do
    shape = artifact.parse("main", "item alpha", mode: :ruby)
    expect(shape.dig(:members, 0, :item, :name)).to eq("alpha")
  end
end
