# frozen_string_literal: true

require "parsanol"

# ruby#357: a repetition whose iteration fails PART-WAY (an ordered
# choice's partial alternative consumed, then a later element died)
# must roll the input back to the iteration's start — the rep ends at
# the last successful iteration's end, and a multi-character RE match
# consumes its full length. Without both, `x *( pq "OR" pq y )`
# accepted operator-suffixed junk ("a OR") and the "A" vanished from
# "a AND".
RSpec.describe "repetition rollback across engines (ruby#357)" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  def atom_for(source, rule)
    doc = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(doc).atoms.fetch(rule)
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
    atom = atom_for(<<~PARG, "orx")
      grammar Rollback2 version "1.0.0" {
        entry main: orx
        pq = *( %x20 )
        name = 1*( %x41-5A / %x61-7A )
        primary = name / ( "(" pq orx pq ")" )
        andx = primary *( pq "AND" pq primary )
        orx = andx *( pq "OR" pq andx )
      }
    PARG
    expect { atom.parse("a OR", consume_all: true) }
      .to raise_error(Parsanol::ParseFailed)
  end

  describe "the gem VM (Base#parse fast path)" do
    it "rejects operator-suffixed junk on both editions" do
      %w[v1 v2].each do |edition|
        doc = Parsanol::PARG::Parser.new(<<~PARG).parse
          grammar RollbackVm version "1.0.0" edition "#{edition}" {
            entry main: orx
            pq = *( %x20 )
            name = 1*( %x41-5A / %x61-7A )
            primary = name / ( "(" pq orx pq ")" )
            andx = primary *( pq "AND" pq primary )
            orx = andx *( pq "OR" pq andx )
          }
        PARG
        atoms = Parsanol::PARG::Compiler.compile(doc).atoms
        expect { atoms.fetch("orx").parse("a OR", consume_all: true) }
          .to raise_error(Parsanol::ParseFailed)
      end
    end
  end
end
