# frozen_string_literal: true

module Parsanol
  module Atoms
    # PARG runtime-state atoms (parsanol-ruby#129): per-parse mutable
    # slots living in the parse context's capture store, so capture
    # rollback, scope discipline and the dispatch semantics are the
    # proven dynamic-callback ones. All four are pure data — they
    # serialize as structured tags and rebuild identically in any
    # runtime that implements the state machine.
    class StateBase < Base
      def cached?
        false
      end

      private

      # Slots and captures may live in a parent scope frame (an earlier
      # element's frame); Scope#[] only reads the active one.
      def lookup(context, key)
        context.captures.fetch(key)
      rescue Parsanol::Scope::UndefinedVariable
        nil
      end

      def mark_unsafe(context)
        # The atom reads mutable parse state (captures), so no enclosing
        # composite result may be memoized — replaying it would skip the
        # re-evaluation (same contract as Atoms::Dynamic).
        context.mark_cache_unsafe!
      end
    end

    # Writes a state slot. Two forms: a literal value (always succeeds,
    # consumes nothing) or an inline expression — the expression matches
    # at the position and the slot stores its consumed text (the
    # block_open pattern: match the delimiter, remember it).
    class StateSet < StateBase
      def initialize(slot, value: nil, atom: nil)
        super()
        @slot = slot
        @value = value
        @atom = atom
      end

      attr_reader :slot, :value, :atom

      def try(source, context, _consume_all)
        mark_unsafe(context)
        if @atom.nil?
          context.captures[@slot] = @value
          return [true, ""]
        end

        start = source.bytepos
        outcome = @atom.apply(source, context, false)
        return outcome unless outcome.first

        span = source.input.byteslice(start, source.bytepos - start)
        context.captures[@slot] = span
        outcome
      end

      def to_s_inner(_prec)
        "set #{@slot}=#{@value || '…'}"
      end
    end

    # Matches the state slot's current value verbatim at the position —
    # the block-delimiter comparison ("exactly what was captured above").
    class StateMatch < StateBase
      def initialize(slot)
        super()
        @slot = slot
      end

      attr_reader :slot

      def try(source, context, _consume_all)
        mark_unsafe(context)
        expected = lookup(context, @slot)
        return [false, nil] if expected.nil?

        actual = source.peek(expected.length)
        return [false, nil] if actual != expected

        source.bytepos += expected.length
        [true, actual]
      end

      def to_s_inner(_prec)
        "state(#{@slot})"
      end
    end

    # Dispatches on the slot's current value to a rule reference. The
    # resolver maps a rule name to its atom lazily (rules may still be
    # under construction when this atom is built). A nil arm fails the
    # atom — the native dynamic-callback parity.
    class StateSwitch < StateBase
      def initialize(slot, arms, default, resolver)
        super()
        @slot = slot
        @arms = arms
        @default = default
        @resolver = resolver
      end

      attr_reader :slot, :arms, :default

      def try(source, context, consume_all)
        mark_unsafe(context)
        current = lookup(context, @slot)
        rule_name = @arms[current] || @default
        return [false, nil] if rule_name.nil?

        @resolver.call(rule_name).apply(source, context, consume_all)
      end

      def to_s_inner(_prec)
        "switch(#{@slot})"
      end
    end

    # A foreign atom: a class resolved from the artifact's customs
    # binding at compile time. The instance runs as-is on the Ruby
    # engine; the serialized tag carries the binding so any runtime can
    # decide support loudly.
    class CustomRef < Base
      def initialize(name, klass)
        super()
        @name = name
        @atom = klass.new
      end

      attr_reader :name

      def cached?
        false
      end

      def try(source, context, consume_all)
        @atom.try(source, context, consume_all)
      end

      def to_s_inner(_prec)
        "custom(#{@name})"
      end
    end
  end
end
