# Deterministic asciichem benchmark corpus generator.
#
# Candidates come from the asciichem-tests conformance fixtures (every
# case that carries an `input` and is not a linter or convention case,
# matching the asciichem-rs acceptance contract); only inputs the
# vendored artifact accepts are written. The corpus is name -> document
# text, the same shape as json_inputs.json, so every harness consumes it
# with the asciichem artifact and entry "formula".
#
# Usage (needs the vendored artifact only):
#   bundle exec ruby benchmark/sota/corpora/gen_asciichem_corpus.rb
# Override the fixtures checkout with ASCIICHEM_TESTS (default:
# ~/src/asciichem/asciichem-tests, asciichem-tests commit recorded in
# ../asciichem/BUILT_FROM).
require "json"
require "parsanol"

ROOT = File.expand_path("..", __dir__)
ARTIFACT = File.join(ROOT, "asciichem", "asciichem.artifact.json")
OUT = File.join(__dir__, "asciichem_inputs.json")
DEFAULT_FIXTURES = File.expand_path("~/src/asciichem/asciichem-tests/corpus/fixtures")
FIXTURES = File.expand_path(ENV.fetch("ASCIICHEM_TESTS", DEFAULT_FIXTURES))

entries = Dir.children(FIXTURES).select { |name| name.end_with?(".json") }.sort
candidates = entries.flat_map do |name|
  JSON.parse(File.read(File.join(FIXTURES, name))).filter_map do |fixture|
    next if fixture.is_a?(Hash) && (fixture["lint"] || fixture["convention"])

    fixture.is_a?(Hash) && fixture["input"].is_a?(String) ? fixture["input"] : nil
  end
end.uniq

artifact = Parsanol::PARG::Artifact.load(ARTIFACT)
accepted = candidates.filter_map do |text|
  artifact.parse("formula", text, mode: :ruby)
  text
rescue Parsanol::ParseFailed, StandardError
  nil
end

docs = accepted.each_with_index.to_h { |text, index| [format("chem_%03d", index), text] }
File.write(OUT, JSON.generate(docs))
puts "asciichem corpus: #{docs.size} documents from #{accepted.size} accepted " \
     "of #{candidates.size} fixtures, #{docs.values.sum(&:bytesize)} bytes"
