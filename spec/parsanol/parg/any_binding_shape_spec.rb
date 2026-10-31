# frozen_string_literal: true

require "parsanol"
require "json"

# parsanol-ruby#383: the (any) passthrough delivered ENGINE-DEPENDENT
# shapes (ruby Slice graphs, native wire objects, wasm plain strings),
# so (any)-bound keys could not survive a cross-engine gate. (any) now
# reduces to the ONE plain shape: scalars and capture leaves as their
# text, named groups as string-keyed plain hashes, repeats as arrays.
RSpec.describe "(any) binding shape" do
  def artifact
    source = <<~PARG
      grammar AnyShape version "1.0.0" edition 2 {
        word = 1*( %x41-5A / %x61-7A )
        digit = %x30-39
        dash = "-"
        number = ( word ) as name
        suffix = ( dash ( 1*( digit ) ) as num )
        identifier = number suffix
        entry identifier: identifier
        bindings identifier {
          name -> name (any)
          num -> num (any)
        }
        test {
          accept "ABC-12"
        }
      }
    PARG
    envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
    Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
  end

  it "delivers plain strings and hashes, engine-independently" do
    bound = artifact.parse_and_bind("identifier", "ABC-12")
    expect(bound).to eq(name: "ABC", num: "12")
  end

  it "reduces a group capture to a plain string-keyed hash" do
    source = <<~PARG
      grammar AnyShape2 version "1.0.0" edition 2 {
        digit = %x30-39
        colon = ":"
        pair = ( ( 1*( digit ) ) as num colon ( 1*( digit ) ) as rev ) as whole
        identifier = pair
        entry identifier: identifier
        bindings identifier {
          whole -> whole (any)
        }
        test {
          accept "12:34"
        }
      }
    PARG
    envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
    bound = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
      .parse_and_bind("identifier", "12:34")
    expect(bound).to eq(whole: { "num" => "12", "rev" => "34" })
  end
end
