# frozen_string_literal: true

module Parsanol
  module PARG
    # F10 phase 2: the artifact-driven front end.
    #
    # The parg artifact is the parser of record: SelfHost.validate accepts
    # or rejects the source with the native engine before anything else.
    # Document construction then routes each top-level item —
    # line-classified, since PARG's document grammar is line-oriented
    # (PN 1) — through the reference semantics. Acceptance gate: the
    # compiled envelope checksum must equal the reference compiler's for
    # every grammar in the corpus.
    module Frontend
      NAMED_SECTION = /\A(render|bindings)\s+(\w+)\s*\{/
      PREPROCESS_SECTION = /\Apreprocess\s+(\w+)\s*\{/
      DERIVE_LINE = /\Aderive\s+(\w+)\s+"((?:[^"\\]|\\.)*)"/
      TEST_SECTION = /\Atest\s*\{/
      RULE_LINE = /\A([a-z_][a-z0-9_]*)\s*=\s*/
      ENTRY_LINE = /\Aentry\s+(\w+)\s*:\s*(\w+)/
      USE_LINE = /\Ause\s+(\w+)/
      GRAMMAR_LINE = /\Agrammar\s+(\w+)\s+version\s+"([^"]+)"/
      # The capture-edition tail: the canonical numeric spelling or the
      # quoted aliases (ruby#361); `mode` stays the deprecated keyword.
      EDITION_TAIL = /
        \s+(?:edition\s+(?:"(?<quoted>[^"]+)"|(?<number>\d+))|mode\s+"(?<mode>[^"]+)")
      /x
      GLUE_LINE = /\Aglue\s+([a-z_][a-z0-9_]*(?:\s+[a-z_][a-z0-9_]*)*)\s*\z/

      module_function

      # Brace depth for the line-oriented collection: braces inside
      # string literals are grammar data — test pins quote whole
      # language forms, including deliberately malformed ones whose
      # unbalanced braces would push the section depth off (ruby#369).
      def brace_delta(line)
        bare = line.gsub(/"(?:[^"\\]|\\.)*"/, "")
        bare.scan("{").count - bare.scan("}").count
      end

      def parse(source)
        SelfHost.validate(source) unless SelfHost.available? && !SelfHost.valid?(source)

        document = Document.new
        document.source = source
        state = { section: nil, section_name: nil, section_lines: [],
                  depth: 0, doc_comments: [], rule_lines: {},
                  entry_lines: [] }
        deferred = []
        preprocess_texts = []
        document.own_entries ||= []

        source.each_line do |line|
          stripped = line.strip
          if stripped.start_with?("##")
            state[:doc_comments] << stripped.sub(/\A##\s?/, "")
            next
          end
          next if stripped.empty? || stripped.start_with?("#")

          if state[:rule_depth]&.positive?
            # A brace-form rule body spans lines (ruby#311): keep
            # appending until its braces balance.
            state[:rule_lines][state[:rule_depth_name]] << line
            state[:rule_depth] += brace_delta(line)
            if state[:rule_depth].zero?
              merge_rule(document, state[:rule_lines][state[:rule_depth_name]])
              state[:rule_depth] = nil
              state[:rule_depth_name] = nil
            end
          elsif state[:section]
            advance_section(document, state, line, deferred, preprocess_texts)
          else
            route_top_level(document, stripped, line, state,
                            preprocess_texts)
          end
        end

        replay_deferred(document, deferred, state[:rule_lines],
                        state[:entry_lines], preprocess_texts)
        document
      end

      # Consumes one line inside a deferred/closed-by-brace section.
      def advance_section(document, state, line, deferred, preprocess_texts)
        section = state[:section]
        state[:depth] += brace_delta(line)
        if state[:depth].positive?
          preprocess_texts.last << line if section == "preprocess"
          state[:section_lines] << line
          return
        end

        case section
        when "test"
          deferred << ["test {", state[:section_lines]]
        when "bindings"
          deferred << ["bindings #{state[:section_name]} {", state[:section_lines]]
        when "preprocess"
          preprocess_texts.last << "}\n"
          close_section(document, section, state[:section_name],
                        state[:section_lines])
        else
          close_section(document, section, state[:section_name],
                        state[:section_lines])
        end
        state[:section] = nil
        state[:section_name] = nil
        state[:section_lines] = []
      end

      def route_top_level(document, stripped, line, state, preprocess_texts)
        doc_comments = state[:doc_comments]

        case stripped
        when USE_LINE
          document.uses << Regexp.last_match(1)
          doc_comments = []
        when GLUE_LINE
          document.glue_rules.concat(Regexp.last_match(1).split)
          doc_comments = []
        when GRAMMAR_LINE
          document.grammar_name = Regexp.last_match(1)
          document.version = Regexp.last_match(2)
          tail = stripped.match(EDITION_TAIL)
          document.edition = if tail.nil?
                               "v1"
                             else
                               level = tail[:number] || tail[:quoted] || tail[:mode]
                               ["2", "v2"].include?(level) ? "v2" : "v1"
                             end
          doc_comments = []
        when NAMED_SECTION
          state[:section] = Regexp.last_match(1)
          state[:section_name] = Regexp.last_match(2)
          state[:section_lines] = []
          state[:depth] = 1
          doc_comments = []
        when PREPROCESS_SECTION
          state[:section] = "preprocess"
          state[:section_name] = Regexp.last_match(1)
          state[:section_lines] = []
          preprocess_texts << "preprocess #{state[:section_name]} {\n"
          state[:depth] = 1
          doc_comments = []
        when TEST_SECTION
          state[:section] = "test"
          state[:section_lines] = []
          state[:depth] = 1
          doc_comments = []
        when ENTRY_LINE
          entry_name = Regexp.last_match(1)
          document.entries[entry_name] = Regexp.last_match(2)
          document.own_entries << entry_name
          state[:entry_lines] << line
          doc_comments = []
        when DERIVE_LINE
          document.derive[Regexp.last_match(1)] =
            Regexp.last_match(2).gsub(/\\(.)/, '\1')
          doc_comments = []
        when RULE_LINE
          rule_name = Regexp.last_match(1)
          document.docs[rule_name] = doc_comments.join("\n") unless doc_comments.empty?
          doc_comments = []
          state[:rule_lines][rule_name] = line
          depth = brace_delta(line)
          if depth.positive?
            # Brace-form body opens (ruby#311): the rule completes on a
            # later line; the continuation loop appends and merges then.
            state[:rule_depth] = depth
            state[:rule_depth_name] = rule_name
          else
            merge_rule(document, line)
          end
        else
          doc_comments = []
        end
        state[:doc_comments] = doc_comments
      end

      # Deferred test/bindings sections re-parse against a mini preamble
      # built from the collected rule/entry/preprocess text.
      def replay_deferred(document, deferred, rule_lines, entry_lines,
                          preprocess_texts)
        return if deferred.empty?

        preamble = "grammar Mini version \"1\" {\n" \
                   "#{rule_lines.values.join}#{entry_lines.join}" \
                   "#{preprocess_texts.join}}\n"
        deferred.each do |(opener, lines)|
          text = "#{preamble[0..-2]}#{opener}\n#{lines.join}}\n"
          mini = Parser.new(text).parse
          if opener.start_with?("test")
            document.tests.concat(mini.tests)
          else
            document.bindings.merge!(mini.bindings)
          end
        end
      end

      def merge_rule(document, line)
        mini = Parser.new("grammar Mini version \"1\" {\n#{line}}\n").parse
        document.rules.merge!(mini.rules)
        mini.docs.each { |rule, text| document.docs[rule] = text }
      end

      def close_section(document, kind, name, lines)
        mini = Parser.new("grammar Mini version \"1\" {\nb = \"q\"\n}#{kind} #{name} {\n#{lines.join}}\n").parse
        document.bindings.merge!(mini.bindings)
        document.preprocess.merge!(mini.preprocess)
        document.render.merge!(mini.render)
        document.derive.merge!(mini.derive)
      end
    end
  end
end
