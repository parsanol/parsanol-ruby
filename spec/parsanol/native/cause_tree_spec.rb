# frozen_string_literal: true

require "spec_helper"

# Native failures must diagnose from Rust-side tracking (deepest failure
# position + expected terminals) without a Ruby reporter reparse.
RSpec.describe "native cause diagnostics", :native do
  def interpreter_position(atom, input)
    atom.parse(input, mode: :ruby)
    nil
  rescue Parsanol::ParseFailed => e
    deepest = lambda do |cause|
      [cause.position, *cause.children.map(&deepest)].max
    end
    cause = e.parse_failure_cause
    cause ? deepest.call(cause) : nil
  end

  def native_failure(atom, input)
    Parsanol::Native.parse(atom, input)
    nil
  rescue Parsanol::ParseFailed => e
    e
  end

  shared_examples "native cause parity" do |input|
    it "reports the same deepest position as the interpreter for #{input.inspect}" do
      err = native_failure(subject_atom, input)
      expect(err).not_to be_nil, "native accepted #{input.inspect}"
      expect(err.parse_failure_cause.position)
        .to eq(interpreter_position(subject_atom, input))
    end
  end

  describe "str + required repetition" do
    subject(:subject_atom) { Parsanol.str("ab") >> Parsanol.match("[0-9]").repeat(1).as(:n) }

    it "raises with expected terminals and position" do
      err = native_failure(subject_atom, "abx")
      expect(err.message).to include("[0-9]")
      expect(err.message).to include("line 1 char 3")
      expect(err.parse_failure_cause.position).to eq(2)
    end

    it_behaves_like "native cause parity", "abx"
    it_behaves_like "native cause parity", "ab"
    it_behaves_like "native cause parity", "ax"
    it_behaves_like "native cause parity", ""
  end

  describe "alternation deepest expectation" do
    subject(:subject_atom) do
      (Parsanol.str("foo") >> Parsanol.str("!")) |
        (Parsanol.str("bar") >> Parsanol.match("[0-9]"))
    end

    it_behaves_like "native cause parity", "foX"
    it_behaves_like "native cause parity", "bar!"
    it_behaves_like "native cause parity", "zzz"
  end

  describe "multiline position" do
    subject(:subject_atom) { Parsanol.str("a\nb") >> Parsanol.match("[x-z]").repeat(1) }

    it "computes line and column from the byte offset" do
      err = native_failure(subject_atom, "a\nbq")
      expect(err.message).to include("line 2 char 2")
    end
  end
end
