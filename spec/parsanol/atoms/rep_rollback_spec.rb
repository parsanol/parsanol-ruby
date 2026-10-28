# frozen_string_literal: true

require "parsanol"

# ruby#357: a repetition whose iteration fails PART-WAY (an ordered
# choice's partial alternative consumed, then a later element died)
# must roll the input back to the iteration's start — the rep ends at
# the last successful iteration's end. Without the restore,
# `x *( pq "OR" pq y )` accepted operator-suffixed junk ("a OR").
RSpec.describe "repetition rollback on a failed iteration" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  it "rejects operator-suffixed trailing junk at the top level" do
    env = compile(<<~PARG)
      grammar Rollback version "1.0.0" {
        entry main: orx
        pq = *( %x20 )
        name = 1*( %x41-5A / %x61-7A )
        primary = name / ( "(" pq orx pq ")" )
        andx = primary *( pq "AND" pq primary )
        orx = andx *( pq "OR" pq andx )
        test {
          accept "a AND b"
          reject "a OR"
          reject "a AND"
        }
      }
    PARG
    expect(env["tests"]).to be_truthy
  end

  it "rolls back a partial iteration in the atom interpreter" do
    doc = Parsanol::PARG::Parser.new(<<~PARG).parse
      grammar Rollback2 version "1.0.0" {
        entry main: orx
        pq = *( %x20 )
        name = 1*( %x41-5A / %x61-7A )
        primary = name / ( "(" pq orx pq ")" )
        andx = primary *( pq "AND" pq primary )
        orx = andx *( pq "OR" pq andx )
      }
    PARG
    atoms = Parsanol::PARG::Compiler.compile(doc).atoms
    atom = atoms.fetch("orx")
    expect { atom.parse("a OR", consume_all: true) }
      .to raise_error(Parsanol::ParseFailed)
  end
end


# The gem's internal VM (Base#parse's VM.program_for fast path) keeps a
# failed iteration's partial state: the second or-level iteration
# matches "OR" + the empty pq, fails on the trailing primary, and the
# tree still materializes {"pq" => [], "andx" => "R"@3} — and the parse
# SUCCEEDS on both dialects. Tracked on ruby#357; pending until the
# VM's REP_TEST/REP_STEP/K_REP bookkeeping drops the failed iteration.
RSpec.describe "repetition rollback in the gem VM (ruby#357)" do
  it "rejects operator-suffixed junk on both dialects", pending: "ruby#357" do
    %w[v1 v2].each do |mode|
      doc = Parsanol::PARG::Parser.new(<<~PARG).parse
        grammar RollbackVm version "1.0.0" {
          entry main: orx
          pq = *( %x20 )
          name = 1*( %x41-5A / %x61-7A )
          primary = name / ( "(" pq orx pq ")" )
          andx = primary *( pq "AND" pq primary )
          orx = andx *( pq "OR" pq andx )
        }
      PARG
      doc.mode = mode
      atoms = Parsanol::PARG::Compiler.compile(doc).atoms
      expect { atoms.fetch("orx").parse("a OR", consume_all: true) }
        .to raise_error(Parsanol::ParseFailed)
    end
  end
end
