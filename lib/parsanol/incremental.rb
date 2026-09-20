# frozen_string_literal: true

module Parsanol
  # Incremental parsing over a persistent Rust-side session
  # (TODO.perf/4): the memo window that an edit provably did not
  # touch is retained across parses, so a keystroke re-parse costs
  # the edit's neighborhood instead of the whole document.
  #
  # Grammars with Dynamic atoms are not eligible (no Ruby re-entry
  # while the input is borrowed); build sessions from plain grammars.
  #
  # @example
  #   session = Parsanol::IncrementalSession.new(parser.root_atom)
  #   session.parse(doc)                                    # full parse
  #   session.parse_with_edit(doc, offset: 42, old_length: 1, new_length: 3)
  #   session.release
  #
  class IncrementalSession
    # @param root_atom [Object] a grammar root atom (the same object
    #   a Parsanol::Parser rule produces)
    def initialize(root_atom)
      unless Native.available?
        raise NativeUnavailable, "parsanol native extension not loaded"
      end

      @session = Native._incremental_session(Native::Parser.serialize_grammar(root_atom))
    end

    # Full parse (also the session's first call).
    #
    # @param input [String]
    # @return [Object] the parslet-shaped tree
    def parse(input)
      Native._incremental_parse(@session, input, -1, 0, 0)
    end

    # Re-parse after a single edit described by its span.
    #
    # @param input [String] the document AFTER the edit
    # @param offset [Integer] byte offset of the edit
    # @param old_length [Integer] bytes removed
    # @param new_length [Integer] bytes inserted
    # @return [Object] the parslet-shaped tree
    def parse_with_edit(input, offset:, old_length:, new_length:)
      Native._incremental_parse(@session, input, offset, old_length, new_length)
    end

    # Session cache counters: [hits, misses].
    #
    # @return [Array(Integer, Integer)]
    def stats
      Native._incremental_stats(@session)
    end

    # Free the Rust-side session. The session becomes unusable.
    #
    # @return [Boolean] true when a session was freed
    def release
      released = Native._incremental_release(@session)
      @session = nil
      released
    end
  end
end
