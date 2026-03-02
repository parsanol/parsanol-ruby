# frozen_string_literal: true

# Parser atoms - the building blocks for grammars.
# Each atom type handles a specific parsing primitive or combinator.
module Parsanol
  module Atoms
    # Precedence levels for pretty-printing.
    # Higher values bind more loosely.
    module Precedence
      ATOM       = 1  # literals, entities
      LOOKAHEAD  = 2  # &expr, !expr
      REPETITION = 3  # expr*, expr+, expr?
      SEQUENCE   = 4  # expr expr
      CHOICE     = 5  # expr | expr
      TOP        = 6  # outer level

      # Backward-compatible aliases
      BASE      = ATOM
      ALTERNATE = CHOICE
      OUTER     = TOP
    end

    # Load atom implementations
    require 'parsanol/atoms/can_flatten'
    require 'parsanol/atoms/context'
    require 'parsanol/atoms/dsl'
    require 'parsanol/atoms/base'
    require 'parsanol/atoms/custom'
    require 'parsanol/atoms/ignored'
    require 'parsanol/atoms/named'
    require 'parsanol/atoms/lookahead'
    require 'parsanol/atoms/cut'
    require 'parsanol/atoms/alternative'
    require 'parsanol/atoms/sequence'
    require 'parsanol/atoms/repetition'
    require 'parsanol/atoms/re'
    require 'parsanol/atoms/str'
    require 'parsanol/atoms/entity'
    require 'parsanol/atoms/capture'
    require 'parsanol/atoms/dynamic'
    require 'parsanol/atoms/scope'
    require 'parsanol/atoms/infix'
    # Load visitor pattern (must be after all atom classes)
    require 'parsanol/atoms/visitor'
  end
end
