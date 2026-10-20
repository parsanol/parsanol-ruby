# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#245: the reported contamination appears after interleaved
# parse -> consumer-walk -> parse cycles in one process. This pins the
# parser side: memo tables are per-parse, so repeated parses of the same
# source must return identical trees no matter what consumed earlier
# results.
class CrossParseIsolationParser < Parsanol::Parser
  root(:document)

  rule(:document) { (entity >> eol).repeat(1) }
  rule(:entity) { str("ENTITY ") >> ident.as(:name) >> str(" DERIVE ") >> attr >> str(";") }
  rule(:attr) do
    ident.as(:attr) >> str(" : ") >> ident.as(:type) >> str(" := ") >>
      (match("[0-9]").repeat(1) >> str(".") >> match("[0-9]").repeat(1)).as(:value)
  end
  rule(:ident) { match("[A-Za-z0-9]").repeat(1) }
  rule(:eol) { str("\n") }
end

RSpec.describe "cross-parse isolation" do
  def source(index)
    "ENTITY e#{index} DERIVE narrow : INTEGER := #{index}.5;\n"
  end

  # A consumer walk over the parsed tree, standing in for the model
  # builder/checker passes in the report.
  def walk(value)
    case value
    when Hash then value.each { |key, item| walk(key) && walk(item) }
    when Array then value.each { |item| walk(item) }
    else value.to_s.length
    end
  end

  %i[native ruby].each do |mode|
    it "returns identical trees after interleaved parse+walk cycles (#{mode})" do
      parser = CrossParseIsolationParser.new
      sources = Array.new(13) { |index| source(index) }
      baseline = sources.map { |text| parser.parse(text, mode: mode).inspect }

      3.times do
        sources.each_with_index do |text, index|
          result = parser.parse(text, mode: mode)
          walk(result)
          expect(result.inspect).to eq(baseline[index]),
                                    "fixture #{index} drifted in #{mode} after a parse+walk cycle"
        end
      end

      # Alternating inputs is the sharpest cross-input check: a memo entry
      # served across inputs would show up here immediately.
      sources.first(6).each do |text|
        parser.parse(text, mode: mode)
        parser.parse(sources.last, mode: mode)
      end
      sources.each_with_index do |text, index|
        expect(parser.parse(text, mode: mode).inspect).to eq(baseline[index]),
                                                          "fixture #{index} drifted after interleaving in #{mode}"
      end
    end
  end
end
