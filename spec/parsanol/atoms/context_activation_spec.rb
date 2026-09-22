# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#122: after adaptive activation flips (64 backtrack events
# behind the frontier), the active-path lookup touches memo positions the
# probe phase never populated — @memo[pos] must auto-vivify or the parse
# crashes with NoMethodError on nil under fresh positions.
RSpec.describe "context activation memo safety" do
  it "does not crash when caching activates at an unpopulated position" do
    ok_atom_class = Class.new(Parsanol::Atoms::Base) do
      def try(source, _context, _consume_all)
        source.consume(1)
        ok(source.bytepos)
      end
    end
    fail_atom_class = Class.new(Parsanol::Atoms::Base) do
      def try(_source, _context, _consume_all)
        [false, nil]
      end
    end

    context = Parsanol::Atoms::Context.new(nil)
    source = Parsanol::Source.new("hello world")

    # Advance the frontier (an attempt starting at pos 1 sets it to 1),
    # then generate 64+ backtrack events at pos 0 (each failing attempt
    # lands behind the frontier) so adaptive activation engages.
    source.bytepos = 1
    context.try_with_cache(ok_atom_class.new, source, false)

    fail_atom = fail_atom_class.new
    70.times do
      source.bytepos = 0
      context.try_with_cache(fail_atom, source, false)
    end

    # Active-phase lookup at a position the probe phase never populated.
    source.bytepos = 6
    expect { context.try_with_cache(ok_atom_class.new, source, false) }
      .not_to raise_error
  end
end
