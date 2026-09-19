# frozen_string_literal: true

module Parsanol
  module Native
    # Reference consumer for the flat event stream returned by
    # {Parsanol::Native::Parser.parse_events}: replays the opcode
    # stream into the same tree Parsanol::Native.parse produces.
    #
    # Domain builders (e.g. an EXPRESS model builder) should not
    # rebuild this tree — they consume the events directly, which is
    # the point of the format. This player exists to document the
    # protocol and to conformance-test the stream against the shaped
    # tree.
    #
    # Opcodes (see parsanol-rs portable::events):
    #   0 NIL                  4 BEGIN_ARR   6 BEGIN_HASH
    #   1 STR <pool>           5 END_ARR     7 END_HASH
    #   2 SLICE <offset> <len> 3 KEY <pool>
    class EventPlayer
      OP_NIL = 0
      OP_STR = 1
      OP_SLICE = 2
      OP_KEY = 3
      OP_BEGIN_ARR = 4
      OP_END_ARR = 5
      OP_BEGIN_HASH = 6
      OP_END_HASH = 7

      # One-shot replay: returns the tree for the stream.
      def self.play(events, strings, input)
        player = new(events, strings, input)
        tree = player.read_value
        unless player.pos == events.length
          raise ArgumentError, "event stream not fully consumed"
        end

        tree
      end

      def initialize(events, strings, input)
        @events = events
        @strings = strings
        @input = input
        @pos = 0
      end

      attr_reader :pos

      def read_value
        op = @events[@pos]
        @pos += 1
        case op
        when OP_NIL then nil
        when OP_STR
          value = @strings[@events[@pos]]
          @pos += 1
          value
        when OP_SLICE
          offset = @events[@pos]
          length = @events[@pos + 1]
          @pos += 2
          ::Parsanol::Slice.new(offset, @input.byteslice(offset, length), @input)
        when OP_BEGIN_HASH
          hash = {}
          until @events[@pos] == OP_END_HASH
            @pos += 1 # KEY opcode
            key = symbol(@strings[@events[@pos]])
            @pos += 1
            hash[key] = read_value
          end
          @pos += 1
          hash
        when OP_BEGIN_ARR
          array = []
          until @events[@pos] == OP_END_ARR
            array << read_value
          end
          @pos += 1
          array
        else
          raise ArgumentError, "unknown event opcode #{op} at #{@pos - 1}"
        end
      end

      private

      def symbol(key)
        @@symbol_cache ||= {}
        @@symbol_cache[key] ||= key.to_sym
      end
    end
  end
end
