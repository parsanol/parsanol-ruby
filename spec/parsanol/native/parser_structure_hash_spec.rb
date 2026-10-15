# frozen_string_literal: true

require "spec_helper"
require "parsanol/native"

RSpec.describe Parsanol::Native::Parser do
  describe ".public_structure_hash" do
    it "does not assign object IDs while fingerprinting a fresh grammar" do
      atom = Parsanol::Atoms::Str.new("a") >> Parsanol::Atoms::Str.new("b")
      calls = 0
      trace = TracePoint.new(:call, :c_call) do |event|
        calls += 1 if event.method_id == :object_id
      end

      trace.enable { described_class.public_structure_hash(atom) }

      expect(calls).to eq(0)
    end

    it "distinguishes atoms whose value equality and hash are overridden" do
      literal_class = Class.new(Parsanol::Atoms::Str) do
        def hash
          0
        end

        def eql?(_other)
          true
        end
      end
      atom = literal_class.new("a") >> literal_class.new("b")
      structure = [:seq, [[:str, "a"], [:str, "b"]]]

      expect(described_class.public_structure_hash(atom)).to eq(
        Digest::MD5.hexdigest(structure.to_s),
      )
    end

    it "preserves fingerprints for shared, recursive, binary and custom-label structures" do
      recursive = nil
      recursive = Parsanol::Atoms::Entity.new(:recursive) do
        Parsanol::Atoms::Str.new("a") >> recursive.maybe
      end
      literal = Parsanol::Atoms::Str.new("建物\x00")
      label = proc {}
      atoms = {
        literal >> literal => [:seq, [[:str, "建物\x00"], [:cycle, "Parsanol::Atoms::Str"]]],
        recursive => [:seq, [[:str, "a"], [:rep, 0, 1, [:cycle, "Parsanol::Atoms::Entity"]]]],
        Parsanol::Atoms::Str.new("\xFF".b).as(:binary) => [:named, "binary", [:str, "\xFF".b]],
        Parsanol::Atoms::TriviaCapture.new(literal, { "x" => label }) => [:trivia_capture, [["x", label]], [:str, "建物\x00"]],
      }

      atoms.each do |atom, structure|
        expect(described_class.public_structure_hash(atom)).to eq(
          Digest::MD5.hexdigest(structure.to_s),
        )
      end
    end
  end
end
