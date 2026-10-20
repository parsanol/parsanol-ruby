# frozen_string_literal: true

require "spec_helper"
require "json"
require "fileutils"
require_relative "../../support/random_grammar"

# Cross-engine differential fuzzing, Track A of TODO.sota/8.
#
# Generates seeded random grammars and inputs, compiles them, and asserts
# that every execution path agrees on acceptance and on the canonical tree:
#
#   native (Rust via the extension) == Ruby artifact path (VM+fallback)
#     == Ruby VM program == Ruby interpreter (VM disabled)
#
# With FUZZ_EXPORT_DIR set it writes the artifacts and expected results so
# the wasm runtime can replay the same cases (script/fuzz_wasm.mjs).
RSpec.describe "PARG differential fuzzing" do
  def seed
    value = ENV.fetch("FUZZ_SEED", "").to_s
    value.empty? ? 20_261_020 : Integer(value)
  end

  def case_count
    value = ENV.fetch("FUZZ_CASES", "").to_s
    value.empty? ? 20 : Integer(value)
  end

  def export_dir
    value = ENV.fetch("FUZZ_EXPORT_DIR", "").to_s
    value.empty? ? nil : value
  end

  def canonical(value)
    Parsanol::PARG::Bindings.canonical(value)
  end

  def outcome
    [true, canonical(yield)]
  rescue Parsanol::ParseFailed, Parsanol::ParseError
    [false, nil]
  end

  it "every engine agrees on acceptance and the canonical tree" do
    stats = { compiled: 0, skipped: 0, inputs: 0, accepted: 0, mismatches: [] }
    FileUtils.mkdir_p(export_dir) if export_dir

    RandomGrammar.generate(seed: seed, count: case_count).each_with_index do |fuzz, index|
      document = Parsanol::PARG::Parser.new(fuzz[:source]).parse
      envelope = begin
        Parsanol::PARG::Compiler.compile(document).envelope
      rescue Parsanol::PARG::CompileError => e
        stats[:skipped] += 1
        warn "fuzz grammar #{index} skipped: #{e.message}"
        next
      end
      stats[:compiled] += 1

      artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
      atom = Parsanol::PARG::Compiler.new(document, nil)
        .atom_for(document.entries.fetch(fuzz[:entry]))

      expected = []
      fuzz[:inputs].each do |input|
        stats[:inputs] += 1
        native = outcome { artifact.parse(fuzz[:entry], input, mode: :native) }
        ruby = outcome { artifact.parse(fuzz[:entry], input, mode: :ruby) }
        vm = outcome { atom.parse(input) }
        Parsanol::VM.disable_for!(atom)
        interpreter = outcome { atom.parse(input) }

        stats[:accepted] += 1 if native.first
        results = { native: native, ruby: ruby, vm: vm, interpreter: interpreter }
        unless results.values.uniq.length == 1
          stats[:mismatches] << { grammar: index, input: input, results: results,
                                  source: fuzz[:source] }
        end
        expected << { input: input, accept: native.first, shape: native.last }
      end

      next unless export_dir

      File.write(File.join(export_dir, format("g%03d.artifact.json", index)),
                 JSON.generate(envelope))
      File.write(File.join(export_dir, format("g%03d.cases.json", index)),
                 JSON.generate(cases: expected))
    end

    RSpec.configuration.reporter.message(
      "fuzz stats: #{stats.except(:mismatches)}",
    )
    if stats[:mismatches].any?
      first = stats[:mismatches].first
      warn "first mismatch (grammar #{first[:grammar]}, input #{first[:input].inspect}): " \
           "#{first[:results].inspect}\nsource:\n#{first[:source]}"
    end

    expect(stats[:mismatches]).to be_empty
    expect(stats[:compiled]).to be >= (case_count * 0.7),
                                "generator produced too many uncompilable grammars " \
                                "(#{stats[:skipped]} skipped of #{case_count})"
  end
end
