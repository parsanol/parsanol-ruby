# frozen_string_literal: true

require "spec_helper"

# Issue #38: the second Dynamic.register collided on an
# never-incremented callback id and aborted the Rust core.
RSpec.describe Parsanol::Native::Dynamic, :native do
  it "hands out distinct ids per registration" do
    Parsanol::Native.available?
    skip "native extension not loaded" unless Parsanol::Native::Parser.extension_loaded?

    ids = Array.new(3) do
      described_class.register(->(_ctx) {}, description: "spec callback")
    end
    expect(ids.uniq.size).to eq(3)
  ensure
    ids&.each { |id| described_class.unregister(id) }
  end

  it "is loaded when the serializer references it" do
    expect(defined?(described_class)).to be_truthy
  end
end
