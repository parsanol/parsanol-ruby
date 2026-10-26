# frozen_string_literal: true

require "parsanol"
require "json"

# rs#304: the recovery-quality metrics, cross-engine. This spec ports
# parsanol-rs's tests/recovery_metrics.rs harness exactly — the same
# fixed-LCG corruption stream (verified identical against a
# third-language implementation) — and pins the outcome counts. The
# seeded breadth found the engines diverging (rs 56/64 vs ruby 26/64
# declared, 31 vs 15 kv); the divergence classified into two resync
# contract gaps and both engines converged in one train (rs#304 slice
# 3). The pins below are the SHARED counts: any move here without the
# matching move in the rs harness is engine drift.

# Converged (rs#304): both engines resync from the spine boundary, so
# the counts are engine-identical. The ruby-side gaps (resync gated on
# a non-empty partial; scan anchored at the failure offset) were fixed
# in the same train as the rs half.
ARTIFACTS = {
  "recovery_resync_declared" => 58, # both engines, 64 seeds
  "recovery_kv" => 33,              # both engines, 64 seeds
}.freeze

# The u64 LCG from the Rust harness, verbatim.
class Lcg
  def initialize(seed)
    @state = seed
  end

  def next_u64
    @state = ((@state * 6364136223846793005) + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
    @state >> 11
  end
end

KINDS = %i[delete substitute insert duplicate].freeze

def corrupt(input, seed, count)
  rng = Lcg.new(0x5EED_0000 + seed)
  bytes = input.bytes
  count.times do
    return bytes.push(120) if bytes.empty?

    kind = KINDS[rng.next_u64 % 4]
    pos = rng.next_u64 % bytes.length
    pos -= 1 while (bytes[pos] & 0xC0) == 0x80 && pos.positive?
    case kind
    when :delete then bytes.delete_at(pos)
    when :substitute then bytes[pos] = 122
    when :insert then bytes.insert(pos, 122)
    when :duplicate then bytes.insert(pos, bytes[pos])
    end
  end
  bytes.pack("C*").force_encoding(Encoding::UTF_8)
end

RSpec.describe "recovery quality metrics (cross-engine)" do
  def corpus_dir
    dir = File.expand_path(ENV.fetch("PARG_CONFORMANCE_DIR", "../../../parsanol-rs/corpus/conformance"), __dir__)
    File.directory?(dir) ? dir : nil
  end

  it "reproduces a pinned outcome count on the shared corruption stream" do
    dir = corpus_dir
    skip "conformance corpus not present" unless dir

    ARTIFACTS.each do |name, expected_recoverable|
      text = File.read(File.join(dir, "#{name}.json"))
      artifact = Parsanol::PARG::Artifact.from_json(text)
      envelope = JSON.parse(text)
      entry = envelope.fetch("default_entry")
      clean = envelope["tests"].find { |test| test["kind"] == "accept" }.fetch("input")

      recoverable = 0
      64.times do |seed|
        corrupted = corrupt(clean, seed, 1 + (seed % 3))
        got = artifact.parse_recovering(entry, corrupted)
        recoverable += 1 if got["ok"] || Array(got["resyncs"]).any?
      end

      expect(recoverable).to eq(expected_recoverable),
                             "#{name}: recoverable #{recoverable} != pinned #{expected_recoverable} " \
                             "(a move here without the matching rs#307 harness move is engine drift)"
    end
  end
end
