# frozen_string_literal: true

module Parsanol
  module PARG
    # ruby#306: `parg diff OLD NEW` — semantic classification of grammar
    # changes against the artifact contract. Atoms are compared by
    # canonical rendering, never by JSON bytes, so compiler-version churn
    # and key order never read as a grammar change.
    #
    # Levels: :major breaks consumers (capture/entry/branch removals,
    # binding changes, mode change), :minor extends them (new entries,
    # captures, branches), :patch is behavior-preserving detail (literal
    # fixes, doc changes, added tests). Ambiguous cases land at the
    # higher level with the evidence attached — never guessed down.
    module Diff
      Finding = Struct.new(:level, :kind, :detail)

      SEVERITY = { none: 0, patch: 1, minor: 2, major: 3 }.freeze

      module_function

      def diff(old_envelope, new_envelope)
        findings = []
        findings.concat(diff_edition(old_envelope, new_envelope))
        findings.concat(diff_entries(old_envelope, new_envelope))
        findings.concat(diff_bindings(old_envelope, new_envelope))
        findings.concat(diff_tests(old_envelope, new_envelope))
        findings
      end

      def level(findings)
        findings.reduce(:none) { |acc, finding| higher(acc, finding.level) }
      end

      def higher(left, right)
        SEVERITY[left] >= SEVERITY[right] ? left : right
      end

      def suggest_bump(findings)
        level = level(findings)
        level == :none ? "no bump needed" : "bump #{level}"
      end

      # -- entries ------------------------------------------------------

      def diff_entries(old_env, new_env)
        old_entries = old_env["entries"] || {}
        new_entries = new_env["entries"] || {}
        findings = (old_entries.keys - new_entries.keys).map do |name|
          Finding.new(:major, :entry_removed, "entry #{name.inspect} removed")
        end
        (new_entries.keys - old_entries.keys).each do |name|
          findings << Finding.new(:minor, :entry_added, "entry #{name.inspect} added")
        end
        old_entries.each do |name, old_entry|
          new_entry = new_entries[name]
          next unless new_entry

          findings.concat(diff_entry(name, old_entry, new_entry))
        end
        findings
      end

      def diff_entry(name, old_entry, new_entry)
        old_atoms = old_entry.dig("grammar", "atoms") || []
        new_atoms = new_entry.dig("grammar", "atoms") || []
        old_root = old_entry.dig("grammar", "root")
        new_root = new_entry.dig("grammar", "root")
        return [Finding.new(:major, :entry_changed, "entry #{name.inspect} lost its root")] if old_root.nil? || new_root.nil?

        old_render = render_atom(old_atoms, old_root)
        new_render = render_atom(new_atoms, new_root)
        return [] if old_render == new_render

        findings = []
        findings.concat(diff_captures(name, old_render, new_render))
        findings.concat(diff_branches(name, mask(old_render), mask(new_render)))
        if findings.empty?
          findings << if mask(old_render) == mask(new_render)
                        # Same captures, same branches, same structure: the
                        # difference is inside literals, bounds, or trivia markers —
                        # behavior-preserving.
                        Finding.new(:patch, :literal_or_bound_change,
                                    "entry #{name.inspect}: literal/bound/doc-level change")
                      else
                        # Structure reshuffled without a detectable capture or
                        # branch delta — evidence over a guess.
                        Finding.new(:minor, :structure_changed,
                                    "entry #{name.inspect}: structure changed " \
                                    "(no capture or branch removed): " \
                                    "#{mask(old_render)[0, 60]} -> #{mask(new_render)[0, 60]}")
                      end
        end
        findings
      end

      # -- captures -----------------------------------------------------

      def diff_captures(entry_name, old_render, new_render)
        old_names = capture_names(old_render)
        new_names = capture_names(new_render)
        removed = old_names - new_names
        added = new_names - old_names
        removed.map { |n| Finding.new(:major, :capture_removed, "entry #{entry_name.inspect}: capture #{n.inspect} removed") } +
          added.map { |n| Finding.new(:minor, :capture_added, "entry #{entry_name.inspect}: capture #{n.inspect} added") }
      end

      def capture_names(render)
        render.scan(/\(name "([^"]+)"/).flatten.uniq
      end

      # -- alternative branches ----------------------------------------

      # A branch that stops matching is the ambiguous-breaking case:
      # inputs it used to accept now reject. Removed branches are major;
      # added-only is the documented minor.
      def diff_branches(entry_name, old_render, new_render)
        old_branches = alt_branches(old_render)
        new_branches = alt_branches(new_render)
        removed = old_branches - new_branches
        added = new_branches - old_branches
        removed.map { |b| Finding.new(:major, :branch_removed, "entry #{entry_name.inspect}: alternative branch #{b} no longer matches") } +
          added.map { |b| Finding.new(:minor, :branch_added, "entry #{entry_name.inspect}: alternative branch #{b} added") }
      end

      # Literals masked: branch identity is structural, not spelling —
      # a literal fix inside a branch is not that branch's removal.
      def mask(render)
        render.gsub(/str:"[^"]*"/, "str:#").gsub(/const:[^\s)]+/, "const:#")
      end

      # Every alternative branch's canonical rendering, anywhere in the
      # tree (alternatives inside repetitions, groups, captures…).
      # Balanced-paren walk: branches nest.
      def alt_branches(render)
        branches = []
        index = render.index("(alt ")
        while index
          start = index + 5
          depth = 1
          cursor = start
          while depth.positive? && cursor < render.length
            case render[cursor]
            when "(" then depth += 1
            when ")" then depth -= 1
            end
            cursor += 1
          end
          body = render[start...(cursor - 1)]
          child_depth = 0
          current = +""
          body.each_char do |ch|
            case ch
            when "(" then child_depth += 1
            when ")" then child_depth -= 1
            when " "
              if child_depth.zero?
                branches << current unless current.empty?
                current = +""
                next
              end
            end
            current << ch
          end
          branches << current unless current.empty?
          index = render.index("(alt ", cursor)
        end
        branches.uniq.sort
      end

      # -- edition ------------------------------------------------------

      def diff_edition(old_env, new_env)
        old_edition = edition_level(old_env)
        new_edition = edition_level(new_env)
        return [] if old_edition == new_edition

        [Finding.new(:major, :edition_changed,
                     "edition changed #{old_edition.inspect} -> #{new_edition.inspect} " \
                     "(every uncaptured node's tree shape changes)")]
      end

      # Artifacts baked before the numeric surface spell the edition
      # "v1"/"v2"; they mean the same levels, not a change.
      def edition_level(envelope)
        declared = envelope.fetch("edition", 1)
        Artifact::EDITION_ALIASES.fetch(declared, declared)
      end

      # -- bindings -----------------------------------------------------

      def diff_bindings(old_env, new_env)
        old_bindings = old_env["bindings"]
        new_bindings = new_env["bindings"]
        return [] if old_bindings == new_bindings
        return [Finding.new(:minor, :bindings_added, "bindings section added")] if old_bindings.nil?
        return [Finding.new(:major, :bindings_removed, "bindings section removed")] if new_bindings.nil?

        [Finding.new(:major, :bindings_changed,
                     "bindings changed — binding paths/types re-validate " \
                     "against the tree")]
      end

      # -- tests --------------------------------------------------------

      def diff_tests(old_env, new_env)
        old_tests = old_env["tests"].to_a
        new_tests = new_env["tests"].to_a
        return [] if old_tests == new_tests

        # Pins per kind: a pin whose INPUT changed alongside a literal
        # fix is the pin following the grammar (patch), not a removal.
        old_counts = old_tests.each_with_object(Hash.new(0)) { |t, counts| counts[t["kind"]] += 1 }
        new_counts = new_tests.each_with_object(Hash.new(0)) { |t, counts| counts[t["kind"]] += 1 }
        dropped = old_counts.keys.select { |kind| new_counts[kind] < old_counts[kind] }
        unless dropped.empty?
          return [Finding.new(:major, :tests_removed,
                              "#{dropped.join(', ')} pin(s) removed — the contract weakened")]
        end

        [Finding.new(:patch, :tests_added,
                     "test pins changed/added (#{old_tests.size} -> #{new_tests.size})")]
      end

      # -- canonical rendering ------------------------------------------

      # Canonical s-expression of one atom index. Entities resolve; keyed
      # hashes render in fixed field order; nothing escapes — this is a
      # diff key, not output text.
      def render_atom(atoms, idx, depth = 0)
        return "…" if depth > 64

        a = atoms[idx]
        return "missing:#{idx}" if a.nil?

        if (str = a["Str"])
          "str:#{str['pattern'].inspect}"
        elsif (re = a["Re"])
          "re:#{re['pattern']}"
        elsif (sequence = a["Sequence"])
          "(seq #{sequence['atoms'].map { |i| render_atom(atoms, i, depth + 1) }.join(' ')})"
        elsif (alt = a["Alternative"])
          "(alt #{alt['atoms'].map { |i| render_atom(atoms, i, depth + 1) }.join(' ')})"
        elsif (rep = a["Repetition"])
          "(rep #{rep['min']} #{rep['max'].nil? ? '*' : rep['max']} #{rep['tag']} #{render_atom(atoms, rep['atom'], depth + 1)})"
        elsif (named = a["Named"])
          "(name \"#{named['name']}\" #{render_atom(atoms, named['atom'], depth + 1)})"
        elsif (entity = a["Entity"])
          render_atom(atoms, entity["atom"], depth + 1)
        elsif (look = a["Lookahead"])
          "(look #{look['positive'] ? '&' : '!'} #{render_atom(atoms, look['atom'], depth + 1)})"
        elsif (behind = a["Lookbehind"])
          "(behind #{behind['positive'] ? '&' : '!'} #{behind['look'].inspect})"
        elsif a["Cut"]
          "cut"
        elsif (ignore = a["Ignore"])
          "(ignore #{render_atom(atoms, ignore['atom'], depth + 1)})"
        elsif (trivia = a["Trivia"])
          "(trivia #{render_atom(atoms, trivia['atom'], depth + 1)})"
        elsif (capture_trivia = a["TriviaCapture"])
          "(trivia-cap #{capture_trivia['rules'].map { |m, k| "#{m}=#{k}" }.join(',')} " \
            "#{render_atom(atoms, capture_trivia['atom'], depth + 1)})"
        elsif (constant = a["Constant"])
          "const:#{constant['value'].inspect}"
        else
          "unknown:#{a.keys.first}"
        end
      end
    end
  end
end
