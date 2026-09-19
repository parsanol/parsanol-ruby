# frozen_string_literal: true

require "spec_helper"

RSpec.describe Parsanol::Native::Parser, :native do
  include Parsanol
  extend Parsanol

  describe ".parse_events" do
    let(:grammar) { str("SCHEMA ") >> match("[a-z]+").repeat(1).as(:name) >> str(";") }
    let(:input) { "SCHEMA test;" }

    it "returns a flat opcode stream and string pool" do
      events, strings = described_class.parse_events(grammar, input)
      expect(events).to be_an(Array)
      expect(events).to all(be_an(Integer))
      expect(strings).to be_an(Array)
    end

    it "replays to the same tree as Native.parse" do
      events, strings = described_class.parse_events(grammar, input)
      replayed = Parsanol::Native::EventPlayer.play(events, strings, input)
      expect(replayed).to eq(Parsanol::Native.parse(grammar, input))
    end

    it "preserves slice positions" do
      events, strings = described_class.parse_events(grammar, input)
      tree = Parsanol::Native::EventPlayer.play(events, strings, input)
      expect(tree[:name]).to be_a(Parsanol::Slice)
      expect(tree[:name].to_s).to eq("test")
      expect(tree[:name].offset).to eq(7)
    end
  end
end
