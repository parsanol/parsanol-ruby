# frozen_string_literal: true

# ruby#336: the contention repro harness. Two phases:
#
#   1. BASELINE — parse every pubid-grammar corpus case solo, record
#      each tree's canonical hash.
#   2. REPLAY — under the caller's CPU contention (spawn spinner
#      processes separately), re-parse the same cases in a loop and
#      compare against the baseline. Any divergence prints the flavor,
#      case, iteration, and both trees, and exits 1.
#
# Usage:
#   ruby tools/contention_replay.rb ARTIFACTS_DIR CORPORA_DIR [LOOPS]
#
# Everything is version-pinned by the invoking environment (the gem
# whose ext is loaded). No instrumentation inside the replay loop.

require "parsanol"
require "json"

artifacts_dir = ARGV.fetch(0)
corpora_dir = ARGV.fetch(1)
loops = (ARGV[2] || "20").to_i
tables_dir = ENV.fetch("TABLES_DIR", File.join(File.dirname(artifacts_dir), "tables"))
imports_dir = ENV.fetch("IMPORTS_DIR", File.join(File.dirname(artifacts_dir), "grammars"))

flavors = Dir.children(corpora_dir).sort.select do |flavor|
  File.exist?(File.join(artifacts_dir, "#{flavor}.json")) &&
    File.exist?(File.join(corpora_dir, flavor, "corpus.json"))
end

plan = []
flavors.each do |flavor|
  corpus = JSON.parse(File.read(File.join(corpora_dir, flavor, "corpus.json")))
  artifact = Parsanol::PARG::Artifact.from_json(
    File.read(File.join(artifacts_dir, "#{flavor}.json")),
    tables_dir: tables_dir, imports_dir: imports_dir,
  )
  entry = artifact.envelope["default_entry"]
  corpus["cases"].each do |case_data|
    next unless case_data["kind"] == "accept"

    plan << [flavor, artifact, entry, case_data["input"], case_data["parsanol_tree"]]
  end
end

warn "baseline: #{plan.length} cases across #{flavors.length} flavors"

def tree_hash(tree)
  JSON.generate(tree).hash
end

baseline = {}
plan.each_with_index do |(flavor, artifact, entry, input, _), index|
  tree = artifact.parse(entry, input)
  baseline[index] = tree_hash(tree)
rescue Parsanol::ParseFailed, StandardError => e
  warn "baseline parse failed at case #{index} (#{flavor}): #{e.class}: #{e.message[0, 80]}"
  baseline[index] = :error
end

warn "replay: #{loops} loops under caller-provided contention"
divergences = 0
iterations = 0
loops.times do |loop_index|
  plan.each_with_index do |(flavor, artifact, entry, input, _want_tree), index|
    iterations += 1
    tree = artifact.parse(entry, input)
    got = tree_hash(tree)
    if got != baseline[index]
      divergences += 1
      puts "DIVERGENCE loop=#{loop_index} case=#{index} flavor=#{flavor} input=#{input.inspect}"
      puts "  baseline: #{baseline[index]}"
      puts "  got:      #{got}"
      puts "  tree:     #{JSON.generate(tree)[0, 400]}"
      exit 1 if divergences >= 5
    end
  rescue Parsanol::ParseFailed, StandardError => e
    divergences += 1
    puts "PARSE FAILURE loop=#{loop_index} case=#{index} flavor=#{flavor} input=#{input.inspect}"
    puts "  #{e.class}: #{e.message[0, 200]}"
    exit 1 if divergences >= 5
  end
end

puts "replay complete: #{iterations} parses, #{divergences} divergences"
exit(divergences.zero? ? 0 : 1)
