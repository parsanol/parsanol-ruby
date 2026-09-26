# frozen_string_literal: true

module Parsanol
  module PG
    # F10 phase 2: the artifact-driven front end.
    #
    # The pg artifact is the parser of record: SelfHost.validate accepts
    # or rejects the source with the native engine before anything else.
    # Document construction then routes each top-level item —
    # line-classified, since PG's document grammar is line-oriented
    # (PN 1) — through the reference semantics. Acceptance gate: the
    # compiled envelope checksum must equal the reference compiler's for
    # every grammar in the corpus.
    module Frontend
      NAMED_SECTION = /\A(render|bindings)\s+(\w+)\s*\{/.freeze
      PREPROCESS_SECTION = /\Apreprocess\s+(\w+)\s*\{/.freeze
      DERIVE_LINE = /\Aderive\s+(\w+)\s+"((?:[^"\\]|\\.)*)"/.freeze
      TEST_SECTION = /\Atest\s*\{/.freeze
      RULE_LINE = /\A([a-z_][a-z0-9_]*)\s*=\s*/.freeze
      ENTRY_LINE = /\Aentry\s+(\w+)\s*:\s*(\w+)/.freeze
      USE_LINE = /\Ause\s+(\w+)/.freeze
      GRAMMAR_LINE = /\Agrammar\s+(\w+)\s+version\s+"([^"]+)"/.freeze

      module_function

      def parse(source)
        SelfHost.validate(source) unless SelfHost.available? && !SelfHost.valid?(source)

        document = Document.new
        document.source = source
        section = nil
        section_name = nil
        section_lines = []
        depth = 0
        rule_lines = {}
        entry_lines = []
        deferred = []
        preprocess_texts = []
        doc_comments = []
        document.own_entries ||= []

        source.each_line do |line|
          stripped = line.strip
          if stripped.start_with?("##")
            doc_comments << stripped.sub(/\A##\s?/, "")
            next
          end
          next if stripped.empty? || stripped.start_with?("#")

          if section
            depth += line.scan("{").count - line.scan("}").count
            if depth <= 0
              if section == "test"
                deferred << ["test {", section_lines]
              elsif section == "bindings"
                deferred << ["bindings #{section_name} {", section_lines]
              elsif section == "preprocess"
                preprocess_texts.last << "}\n"
                close_section(document, section, section_name, section_lines)
              else
                close_section(document, section, section_name, section_lines)
              end
              section = nil
              section_name = nil
              section_lines = []
              next
            end
            preprocess_texts.last << line if section == "preprocess"
            section_lines << line
            next
          end

          case stripped
          when USE_LINE
            document.uses << Regexp.last_match(1)
            doc_comments = []
          when GRAMMAR_LINE
            document.grammar_name = Regexp.last_match(1)
            document.version = Regexp.last_match(2)
            doc_comments = []
          when NAMED_SECTION
            section = Regexp.last_match(1)
            section_name = Regexp.last_match(2)
            section_lines = []
            depth = 1
            doc_comments = []
          when PREPROCESS_SECTION
            section = "preprocess"
            section_name = Regexp.last_match(1)
            section_lines = []
            preprocess_texts << "preprocess #{section_name} {\n"
            depth = 1
            doc_comments = []
          when TEST_SECTION
            section = "test"
            section_lines = []
            depth = 1
            doc_comments = []
          when ENTRY_LINE
            entry_name = Regexp.last_match(1)
            document.entries[entry_name] = Regexp.last_match(2)
            document.own_entries << entry_name
            entry_lines << line
            doc_comments = []
          when DERIVE_LINE
            document.derive[Regexp.last_match(1)] =
              Regexp.last_match(2).gsub(/\\(.)/, '\1')
            doc_comments = []
          when RULE_LINE
            rule_name = Regexp.last_match(1)
            document.docs[rule_name] = doc_comments.join("\n") unless doc_comments.empty?
            doc_comments = []
            rule_lines[rule_name] = line
            merge_rule(document, line)
          else
            doc_comments = []
          end
        end

        unless deferred.empty?
          preamble = "grammar Mini version \"1\" {\n" +
                     rule_lines.values.join + entry_lines.join +
                     preprocess_texts.join + "}\n"
          deferred.each do |(opener, lines)|
            mini = Parser.new(preamble[0..-2] + opener + "\n" + lines.join + "}\n").parse
            if opener.start_with?("test")
              document.tests.concat(mini.tests)
            else
              document.bindings.merge!(mini.bindings)
            end
          end
        end
        document
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
