#!/usr/bin/env ruby
# frozen_string_literal: true

# Statistical performance gate (TODO.perf/5 items 4-5).
#
# Runs the canonical corpus with benchmark-ips, saves the medians as JSON
# and — given --baseline — exits nonzero on a >25% median regression.
# Every number is the median of several ips measurements: single-shot
# wall-clock on shared runners flapped around thresholds (the 0.79x vs
# 0.80x flake), while median-of-N keeps real regressions visible and
# sheds scheduler noise.
#
#   ruby benchmark/ci_gate.rb --save results.json
#   ruby benchmark/ci_gate.rb --baseline results.json --save next.json

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "benchmark/ips"
require "json"
require "optparse"
require "parsanol"
require "parsanol/parslet"

REGRESSION_FRACTION = 0.25
PASSES = 5
IPS_WARMUP = 2
IPS_TIME = 4

module GateCorpus
  ASCIICHEM = %w[
    SO_4^2- H_2O CH_3-CH_2-OH HC#CH Na^+ Cl^-1 Ca^2+
    C_6H_12O_6 H_2O-H_2O CH_3-CH_2-CH_2-CH_3
  ].freeze
  # Deterministic: a baseline is only comparable against the same input.
  ASCIICHEM_BIG = (ASCIICHEM * 100).join("-")

  def self.json_doc(entries)
    {
      name: "perf-gate",
      entries: Array.new(entries) do |i|
        { id: i, name: "entry-#{i}", score: i * 1.5, ok: i.even?,
          tags: %w[a b c], meta: { depth: i % 7, note: nil } }
      end,
    }.to_json.freeze
  end

  JSON_SMALL = json_doc(50).freeze
  JSON_BIG = json_doc(1000).freeze
end

class GateAsciichemParser < Parsanol::Parslet::Parser
  rule(:element) { match(/[A-Z]/) >> match(/[a-z]/).maybe }
  rule(:subscript) { str("_") >> match(/\d/).repeat(1) }
  rule(:superscript) { str("^") >> match(/[0-9+-]/).repeat(1) }
  rule(:atom) { element >> subscript.maybe >> superscript.maybe }
  rule(:bond) { match(/[-=#]/) }
  rule(:molecule) { atom >> (bond.maybe >> atom).repeat }
  root(:molecule)
end

# Label-clean JSON grammar: as() labels must round-trip the native wire
# format, and non-Symbol/String labels (e.g. .as(true)) do not — the
# Ruby tier keeps the boolean key while native yields :true. The gate
# times parsing, so it uses Symbol labels only.
class GateJsonParser < Parsanol::Parser
  rule(:space) { match(/\s/).repeat(1) }
  rule(:space?) { space.maybe }
  rule(:string) do
    str('"') >> ((str("\\") >> any) | (str('"').absent? >> any)).repeat >> str('"')
  end
  rule(:number) do
    str("-").maybe >> match("[0-9]").repeat(1) >>
      (str(".") >> match("[0-9]").repeat(1)).maybe >>
      (match("[eE]") >> match("[+-]").maybe >> match("[0-9]").repeat(1)).maybe
  end
  rule(:true_val) { str("true").as(true) }
  rule(:false_val) { str("false").as(false) }
  rule(:null_val) { str("null").as(:null) }
  rule(:array) do
    str("[") >> space? >>
      (value >> (space? >> str(",") >> space? >> value).repeat).maybe.as(:array) >>
      space? >> str("]")
  end
  rule(:object) do
    str("{") >> space? >>
      (pair >> (space? >> str(",") >> space? >> pair).repeat).maybe.as(:object) >>
      space? >> str("}")
  end
  rule(:pair) { string.as(:key) >> space? >> str(":") >> space? >> value.as(:value) }
  rule(:value) do
    string.as(:string) | number.as(:number) | object | array |
      true_val | false_val | null_val
  end
  rule(:json) { space? >> value >> space? }
  root(:json)
end

JSON_PARSER = GateJsonParser.new
ASCIICHEM_PARSER = GateAsciichemParser.new

def median_ips(label, &block)
  samples = Array.new(PASSES) do
    result = Benchmark.ips(quiet: true, warmup: IPS_WARMUP, time: IPS_TIME) do |x|
      x.report(label, &block)
    end
    result.entries.first.ips
  end
  samples.sort[PASSES / 2]
end

def native?
  defined?(Parsanol::Native) && Parsanol::Native.available?
end

def workloads
  rows = []
  rows << ["asciichem ruby small",
           -> { GateCorpus::ASCIICHEM.each { |i| ASCIICHEM_PARSER.parse(i, mode: :ruby) } }]
  rows << ["asciichem ruby large",
           -> { ASCIICHEM_PARSER.parse(GateCorpus::ASCIICHEM_BIG, mode: :ruby) }]
  rows << ["json ruby small",
           -> { JSON_PARSER.parse(GateCorpus::JSON_SMALL, mode: :ruby) }]
  rows << ["json ruby large",
           -> { JSON_PARSER.parse(GateCorpus::JSON_BIG, mode: :ruby) }]
  if native?
    rows << ["asciichem native small",
             -> { GateCorpus::ASCIICHEM.each { |i| ASCIICHEM_PARSER.parse(i, mode: :native) } }]
    rows << ["asciichem native large",
             -> { ASCIICHEM_PARSER.parse(GateCorpus::ASCIICHEM_BIG, mode: :native) }]
    rows << ["json native small",
             -> { JSON_PARSER.parse(GateCorpus::JSON_SMALL, mode: :native) }]
    rows << ["json native large",
             -> { JSON_PARSER.parse(GateCorpus::JSON_BIG, mode: :native) }]
  end
  rows
end

options = { baseline: nil, save: nil }
OptionParser.new do |opts|
  opts.on("--baseline PATH") { |v| options[:baseline] = v }
  opts.on("--save PATH") { |v| options[:save] = v }
end.parse!

# Sanity: the corpus must parse identically on every tier, or the gate
# would happily time a wrong parse.
GateCorpus::ASCIICHEM.each do |i|
  reference = ASCIICHEM_PARSER.parse(i, mode: :ruby).inspect
  raise "native/ruby mismatch on #{i}" if native? && ASCIICHEM_PARSER.parse(i, mode: :native).inspect != reference
end
json_ref = JSON_PARSER.parse(GateCorpus::JSON_SMALL, mode: :ruby).inspect
raise "native/ruby mismatch on json" if native? && JSON_PARSER.parse(GateCorpus::JSON_SMALL, mode: :native).inspect != json_ref

current = {}
workloads.each do |label, block|
  current[label] = median_ips(label, &block)
  puts format("%-26s %10.1f ips", label, current[label])
end

baseline = options[:baseline] && File.exist?(options[:baseline]) ? JSON.parse(File.read(options[:baseline]))["results"] : nil

puts
puts "| workload | baseline ips | now ips | ratio |"
puts "|---|---|---|---|"
regressed = []
(current.keys | (baseline&.keys || [])).sort.each do |label|
  now = current[label]
  before = baseline&.[](label)
  ratio = now && before ? now / before : nil
  verdict = if ratio.nil?
              "n/a"
            elsif ratio < 1 - REGRESSION_FRACTION
              regressed << label
              "REGRESSED"
            else
              "ok"
            end
  puts format("| %s | %s | %s | %s |", label,
              before ? format("%.1f", before) : "—",
              now ? format("%.1f", now) : "—",
              ratio ? format("%.2f (%s)", ratio, verdict) : "n/a")
end

if options[:save]
  File.write(options[:save], JSON.pretty_generate(
                               "parsanol_version" => Parsanol::VERSION,
                               "ruby" => RUBY_DESCRIPTION,
                               "results" => current,
                             ))
  puts
  puts "saved #{options[:save]}"
end

if regressed.any?
  puts
  puts "REGRESSION (>#{(REGRESSION_FRACTION * 100).to_i}% median slowdown): #{regressed.join(', ')}"
  exit 1
end
puts "gate ok"
