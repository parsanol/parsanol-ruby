# frozen_string_literal: true

# Parser composition DSL - chainable methods for building parser atoms.
# All atoms can use these methods to combine into larger parsers.
#
# Inspired by Parslet (MIT License).

module Parsanol::Atoms::DSL
  # Repeats the current atom between min and max times.
  # If max is nil, there is no upper limit.
  #
  # @example
  #   str('a').repeat           # match zero or more 'a's
  #   str('a').repeat(1, 3)   # match 1-3 `a`s
  def repeat(min = 0, max = nil)
    Parsanol::Atoms::Repetition.new(self, min, max)
  end

  # Matches atom optionally (0 or 1 times).
  # Result is nil if not present, otherwise the matched value.
  #
  # @example
  #   str('foo').maybe   # => nil or 'foo'
  def maybe
    Parsanol::Atoms::Repetition.new(self, 0, 1, :maybe)
  end

  # Ignores the result of a match - returns nil always.
  #
  # @example
  #   str('foo').ignore   # => nil (not 'foo')
  def ignore
    Parsanol::Atoms::Ignored.new(self)
  end

  # Chains two atoms in sequence.
  #
  # @example
  #   str('a') >> str('b')
  def >>(other)
    Parsanol::Atoms::Sequence.new(self, other)
  end

  # Chains two atoms as alternatives (ordered choice).
  #
  # @example
  #   str('a') | str('b')   # matches 'a' or `b`
  def |(other)
    Parsanol::Atoms::Alternative.new(self, other)
  end

  # Negative lookahead - succeeds only if atom is absent.
  #
  # @example
  #   str('a').absent?
  def absent?
    Parsanol::Atoms::Lookahead.new(self, false)
  end

  # Positive lookahead - succeeds only if atom is present.
  #
  # @example
  #   str('a').present?
  def present?
    Parsanol::Atoms::Lookahead.new(self, true)
  end

  # Labels a match for tree output.
  #
  # @example
  #   str('a').as(:b)   # => {:b => 'a'}
  def as(name)
    Parsanol::Atoms::Named.new(self, name)
  end

  # Captures match result for later reference.
  #
  # @example
  #   str('a').capture(:first) >> dynamic { str(ctx.captures[:first]) }
  def capture(name)
    Parsanol::Atoms::Capture.new(self, name)
  end

  # Commit point - prevents backtracking after successful match.
  # Use with caution: cuts prevent backtracking to alternatives.
  #
  # @example
  #   str('if').cut >> condition >> body |
  def cut
    Parsanol::Atoms::Cut.new(self)
  end
end
