# frozen_string_literal: true

require "open3"
require "rbconfig"
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

    it "writes the structural fingerprint without inspecting intermediate arrays" do
      atom = Parsanol::Atoms::Str.new("a") >> Parsanol::Atoms::Str.new("b")
      array_inspections = 0
      trace = TracePoint.new(:c_call) do |event|
        array_inspections += 1 if event.defined_class == Array && event.method_id == :inspect
      end
      fingerprint = nil

      trace.enable { fingerprint = described_class.public_structure_hash(atom) }

      expect(fingerprint).to eq(Digest::MD5.hexdigest("[:seq, [[:str, \"a\"], [:str, \"b\"]]]"))
      expect(array_inspections).to eq(0)
    end

    it "fingerprints nested sequences within a bounded Fiber stack" do
      script = <<~RUBY
        require "parsanol"
        require "parsanol/native"
        atom = Parsanol::Atoms::Str.new("a")
        80.times do
          atom = Parsanol::Atoms::Sequence.new(atom, Parsanol::Atoms::Str.new("b"))
        end
        puts Fiber.new { Parsanol::Native::Parser.public_structure_hash(atom) }.resume
      RUBY
      environment = {
        "RUBY_FIBER_VM_STACK_SIZE" => "32768",
        # Isolate the Ruby frame budget from platform-specific C stack limits.
        "RUBY_FIBER_MACHINE_STACK_SIZE" => "4194304",
      }
      limits = Process.const_defined?(:RLIMIT_CORE) ? { rlimit_core: 0 } : {}
      output, status = Open3.capture2e(environment, RbConfig.ruby,
                                       "-I", File.expand_path("../../../lib", __dir__),
                                       "-e", script, **limits)

      expect(status.exitstatus).to eq(0), output
      expect(output).to eq("de454752d04f42aecccb736d5f2f89f4\n")
    end

    it "preserves fingerprints for each structural atom kind" do
      literal = Parsanol::Atoms::Str.new("x")
      value = { "a" => [1, nil] }
      atoms = {
        Parsanol::Atoms::Re.new("[a-z]") => [:re, "[a-z]"],
        literal | Parsanol::Atoms::Str.new("y") => [:alt, [[:str, "x"], [:str, "y"]]],
        literal.repeat(1, 3) => [:rep, 1, 3, [:str, "x"]],
        literal.present? => [:lookahead, true, [:str, "x"]],
        literal.absent? => [:lookahead, false, [:str, "x"]],
        Parsanol::Atoms::Constant.new(value) => [:constant, value.inspect],
        Parsanol::Atoms::Lookbehind.new(1, /x/, positive: false) => [:lookbehind, 1, /x/, false],
        Parsanol::Atoms::Trivia.new(literal) => [:trivia, [:str, "x"]],
        literal.ignore => [:ignored, [:str, "x"]],
        Parsanol::Atoms::Base.new => [:unknown, "Parsanol::Atoms::Base"],
      }

      atoms.each do |atom, structure|
        expect(described_class.public_structure_hash(atom)).to eq(Digest::MD5.hexdigest(structure.to_s))
      end
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
