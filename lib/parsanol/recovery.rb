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
  end
end
