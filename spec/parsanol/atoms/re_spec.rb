# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Re do
  describe "construction" do
    include Parsanol

    it "allows match(str) form" do
      match("[a]").should be_a(described_class)
    end

    it "allows match[str] form" do
      match["a"].should be_a(described_class)
    end
  end
end
