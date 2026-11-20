# frozen_string_literal: true

require "spec_helper"

# The capture-path slice constructors are UNPOOLED (ruby#535): pooled
# Resettable slices clobbered live AST spans once the 5000-deep pool
# wrapped. The pool object remains available (other lanes may use it),
# but Source#consume / #slice / #consume_bytes hand out independent
# Slice objects and draw nothing from it.
describe "Slice Pooling Integration" do
  it "source has a slice_pool" do
    source = Parsanol::Source.new("hello world")
    expect(source.slice_pool).to be_a(Parsanol::Pools::SlicePool)
  end

  it "source.consume hands out unpooled slices" do
    source = Parsanol::Source.new("hello")

    slice1 = source.consume(1)
    expect(slice1).to be_a(Parsanol::Slice)
    expect(slice1.to_s).to eq("h")

    # The capture path draws nothing from the pool — the statistics
    # stay flat and consecutive slices are distinct objects (no reset
    # clobbering a stored span).
    stats = source.slice_pool.statistics
    expect(stats[:created] + stats[:reused]).to eq(0)

    slice2 = source.consume(1)
    expect(slice2).not_to equal(slice1)
    expect(slice2.to_s).to eq("e")
    expect(slice1.to_s).to eq("h")
  end

  it "source.slice helper hands out unpooled slices" do
    source = Parsanol::Source.new("test")

    slice = source.slice(0, "test")
    expect(slice).to be_a(Parsanol::Slice)
    expect(slice.to_s).to eq("test")

    stats = source.slice_pool.statistics
    expect(stats[:created] + stats[:reused]).to eq(0)
  end

  it "parses repetitive sequences correctly" do
    parser = Class.new(Parsanol::Parser) do
      root :letters
      rule(:letters) { str("a").repeat(10) }
    end.new

    result = parser.parse("aaaaaaaaaa")

    expect(result).to be_a(Parsanol::Slice)
    expect(result.to_s).to eq("aaaaaaaaaa")
  end

  it "handles complex parsing correctly" do
    parser = Class.new(Parsanol::Parser) do
      root :expression
      rule(:expression) do
        (str("x") | str("y")).repeat(5) >>
          str("!")
      end
    end.new

    result = parser.parse("xyxyx!")
    # Result is flattened, so verify parse succeeded
    expect(result).to be_a(Parsanol::Slice)
    expect(result.to_s).to eq("xyxyx!")
  end
end
