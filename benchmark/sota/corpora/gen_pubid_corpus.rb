# Deterministic pubid (ISO flavor) benchmark corpus generator.
#
# Candidates are generated across the identifier shapes the ISO grammar
# accepts, then verified against the vendored artifact; only accepted
# inputs are written. The corpus is name -> document text, the same shape
# as json_inputs.json, so every harness can consume it with the ISO
# artifact and entry "identifier".
require "json"
require "parsanol"

ROOT = File.expand_path("../..", __dir__)
ARTIFACT = File.join(ROOT, "sota", "pubid", "iso.artifact.json")
OUT = File.join(__dir__, "pubid_iso_inputs.json")

publishers = ["ISO", "IEC", "ISO/IEC", "ISO/CEI"]
["", "TS", "TR", "PAS", "DIR", "WD", "WD TS", "DIS", "FDIS"]
numbers = [1, 8601, 25025, 12345, 60027, 80004, 31000, 27001]
parts = ["", "-1", "-2", "-12"]
years = [nil, 1999, 2019, 2020, 2021, 2022, 2024]

candidates = []
stages = [nil, "TS", "PAS", "DIS", "FDIS", "WD TS", "DIR", "TR"]
publishers.each do |publisher|
  stages.each do |stage|
    numbers.first(4).each do |number|
      parts.first(2).each do |part|
        years.first(4).each do |year|
          body = [publisher, stage, "#{number}#{part}", year && ":#{year}"].compact.join(" ")
          candidates << body
        end
      end
    end
  end
end
# Real-world shapes from the contract's conformance corpus.
candidates.push("ISO 8601-1:2019", "ISO/IEC WD TS 25025", "Guide ISO/CEI 51:1999",
                "ISO/IEC DIR 1:2022 + IEC SUP:2022")

artifact = Parsanol::PARG::Artifact.load(ARTIFACT)
accepted = candidates.uniq.filter_map do |text|
  artifact.parse("identifier", text, mode: :ruby)
  text
rescue Parsanol::ParseFailed
  nil
end

# Evenly sample to a bounded corpus: identifiers are short, so thousands
# of near-identical forms measure per-parse overhead rather than variety.
sample_size = 200
step = [accepted.size.fdiv(sample_size).ceil, 1].max
real = candidates.last(4).select { |text| accepted.include?(text) }
docs = (accepted.each_slice(step).map(&:first).first(sample_size) | real)
  .each_with_index.to_h { |text, index| [format("iso_%03d", index), text] }
File.write(OUT, JSON.generate(docs))
puts "pubid corpus: #{docs.size} documents from #{accepted.size} accepted " \
     "of #{candidates.uniq.size} candidates, #{docs.values.sum(&:bytesize)} bytes"
