# Deterministic EXPRESS giant corpus generator.
#
# Copies the two real ISO 10303 schemas from an expressir checkout (the
# 637 KB mathematical-functions schema and the 4 MB concatenated MIM
# oracle), verifies each parses through expressir's parsanol grammar,
# and writes name -> document text — the same corpus shape as
# json_inputs.json. Provenance: ../express/BUILT_FROM.
#
# Usage (inside the expressir checkout's bundle — the verification parse
# needs expressir's grammar and parsanol):
#   cd ~/src/lutaml/expressir && bundle exec \
#     ruby <parsanol>/benchmark/sota/corpora/gen_express_corpus.rb
# Override the checkout with EXPRESSIR_PATH (default ~/src/lutaml/expressir).
require "json"

ROOT = File.expand_path("..", __dir__)
OUT = File.join(__dir__, "express_inputs.json")
DEFAULT_EXPRESSIR = File.expand_path("~/src/lutaml/expressir")
EXPRESSIR = File.expand_path(ENV.fetch("EXPRESSIR_PATH", DEFAULT_EXPRESSIR))

FILES = {
  "express_math_functions_637k" =>
    "spec/syntax/mathematical_functions_schema/mathematical_functions_schema.exp",
  "express_mim_concatenated_4m" =>
    "spec/fixtures/eeng/oracle/description-assignment-mim-concatenated.exp",
}.freeze

require "expressir"

docs = FILES.filter_map do |name, relative|
  path = File.join(EXPRESSIR, relative)
  raise "missing schema #{path}" unless File.file?(path)

  text = File.read(path)
  Expressir::Express::Grammar::Parser.cached_parser.parse(text)
  [name, text]
rescue Parsanol::ParseFailed => e
  raise "#{name} no longer parses: #{e.class}: #{e.message[0, 120]}"
end.to_h

File.write(OUT, JSON.generate(docs))
puts "express corpus: #{docs.size} documents, #{docs.values.sum(&:bytesize)} bytes " \
     "(#{docs.keys.join(', ')})"
