# frozen_string_literal: true

module Parsanol
  # Recovery journaling (TODO.sota/1): when enabled for the current
  # thread, every Named capture appends to a shared journal for the
  # duration of the recovery re-parse. Success paths never enable it —
  # normal parses see only a nil-context check.
  module Recovery
    module_function

    def start_journal
      Thread.current[:parsanol_recovery_journal] = []
      Thread.current[:parsanol_recovery_journaling] = true
      # R1.5 partial-tree collection rides the journaling (recovery)
      # pass: success paths never touch the stash.
      Thread.current[:parsanol_recovery_partial] = nil
      Thread.current[:parsanol_recovery_collect_partial] = true
    end

    # Stops journaling and returns the journal: [name, value] pairs in
    # capture order, including captures from branches that later failed
    # (best-effort superset — same semantics as the rs recovery
    # journal).
    def stop_journal
      Thread.current[:parsanol_recovery_journaling] = false
      journal
    end

    def journal
      Thread.current[:parsanol_recovery_journal] || []
    end

    def journaling?
      Thread.current[:parsanol_recovery_journaling] == true
    end

    # R1.5: the deepest repetition prefix matched before the failure.
    # Repetition failure paths call stash_partial; the furthest-reaching
    # prefix wins. [end_pos, items, tag]
    def stash_partial(end_pos, items, tag)
      return unless Thread.current[:parsanol_recovery_collect_partial]
      return if items.empty? # nothing matched: no partial, like rs

      current = Thread.current[:parsanol_recovery_partial]
      return if current && current[0] >= end_pos

      Thread.current[:parsanol_recovery_partial] = [end_pos, items.dup, tag]
    end

    def take_partial
      value = Thread.current[:parsanol_recovery_partial]
      Thread.current[:parsanol_recovery_partial] = nil
      Thread.current[:parsanol_recovery_collect_partial] = nil
      value
    end
  end
end
