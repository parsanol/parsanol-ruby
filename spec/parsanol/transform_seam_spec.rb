# frozen_string_literal: true

require "spec_helper"

# GH-74: the transform pipeline must route rule execution through the
# public call_on_match seam so subclass overrides run.
RSpec.describe Parsanol::Transform do
  it "invokes the call_on_match override for every matched rule" do
    seen = []
    recorder = ->(bindings) { seen << bindings }
    subclass = Class.new(Parsanol::Transform) do
      rule(w: Parsanol.simple(:x)) { |b| b[:x].to_s.upcase }

      define_method(:call_on_match) do |bindings, block|
        recorder.call(bindings)
        super(bindings, block)
      end
    end

    result = subclass.new.apply({ w: "abc" })
    expect(result).to eq("ABC")
    expect(seen).to eq([{ x: "abc" }])
  end
end
