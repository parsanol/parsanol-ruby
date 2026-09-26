# frozen_string_literal: true

require "json"

module Parsanol
  module PG
    # Command-line tool for authoring and testing PG grammars without any
    # language binding: compile, run the in-file tests, parse inputs
    # interactively, and read the rule documentation.
    #
    #   parsanol pg compile grammars/iso.pg -o iso.json
    #   parsanol pg test grammars/iso.pg
    #   parsanol pg parse grammars/iso.pg "ISO 8601-1:2019"
    #   parsanol pg repl iso.json
    #   parsanol pg doc grammars/iso.pg publisher
    class CLI
      USAGE = <<~TEXT
        usage: parsanol pg <command> <grammar> [arguments]

        commands:
          compile <file.pg> [-o out.json]   compile to an artifact envelope
          test    <file.pg|artifact.json>   run the grammar's test section
          parse   <file> [--entry E] INPUT  parse one input; prints the tree
                                            and the bound captures
          repl    <file> [--entry E]        interactive parse loop (blank
                                            line quits, :quit exits)
          doc     <file> [rule]             print rule documentation

        options:
          --tables DIR   directory for alt-from-table data (default:
                         the grammar file's directory)
      TEXT

      def self.run(argv)
        new(argv).run
      end

      def initialize(argv)
        @argv = argv.dup
        @tables_dir = nil
      end

      def run
        if (index = @argv.index("--tables"))
          @tables_dir = @argv.delete_at(index + 1)
          @argv.delete_at(index)
        end
        command = @argv.shift
        case command
        when "compile" then compile
        when "test" then test
        when "schema" then schema
        when "parse" then parse
        when "repl" then repl
        when "doc" then doc
        else
          warn USAGE
          1
        end
      rescue Parsanol::PG::Error, Parsanol::ParseFailed => e
        warn "#{e.class}: #{e.message}"
        1
      end

      private

      def compile
        source = @argv.shift
        out = flag_value("-o") || default_artifact_name(source)
        envelope = compile_source(source)
        File.write(out, "#{JSON.generate(envelope)}\n")
        puts "#{out}  #{envelope['checksum']}  warnings=#{envelope['lint']['order_warnings'].size}"
        0
      end

      def test
        target = @argv.shift
        if File.directory?(target)
          return batch(target) { |file| artifact_for(file).run_tests }
        end
        artifact = artifact_for(target)
        failures = artifact.run_tests
        suite_dir = flag_value("--suite")
        suites = suite_dir ? Parsanol::PG::Suite.load(suite_dir) : {}
        suites.each_value do |tests|
          failures.concat(artifact.run_test_list(tests))
        end
        if failures.empty?
          puts suites.empty? ? "all tests pass" : "all tests pass (#{suites.keys.join(', ')})"
          0
        else
          failures.each { |failure| warn failure }
          1
        end
      end

      def schema
        ts = @argv.delete("--ts")
        artifact = artifact_for(@argv.shift)
        schema = Parsanol::PG::Schema.from_artifact(artifact)
        if ts
          puts Parsanol::PG::Schema.to_typescript(schema)
        else
          puts JSON.pretty_generate(schema)
        end
        0
      end

      def parse
        file = @argv.shift
        entry = flag_value("--entry")
        input = @argv.join(" ")
        if input.empty?
          warn "usage: parsanol pg parse <file> [--entry E] INPUT"
          return 1
        end
        artifact = artifact_for(file)
        entry_name = entry || artifact.entries.first
        shape = artifact.parse(entry_name, input)
        puts "tree: #{shape.inspect}"
        puts "captures: #{artifact.apply_bindings(entry_name, shape).inspect}"
        0
      end

      def repl
        file = @argv.shift
        entry = flag_value("--entry")
        artifact = artifact_for(file)
        entry_name = entry || artifact.entries.first
        puts "parsanol pg repl — #{file} entry #{entry_name.inspect}; blank line quits"
        loop do
          print "> "
          input = $stdin.gets
          break if input.nil? || input.strip.empty?

          begin
            shape = artifact.parse(entry_name, input.rstrip)
            puts "tree: #{shape.inspect}"
            puts "captures: #{artifact.apply_bindings(entry_name, shape).inspect}"
          rescue Parsanol::ParseFailed => e
            puts "parse failed: #{e.message[0, 160]}"
          end
        end
        0
      end

      def doc
        file = @argv.shift
        rule = @argv.shift
        docs = artifact_for(file).rule_docs
        selected = rule ? { rule => docs[rule] } : docs
        if selected.values.all?(&:nil?)
          warn "no documentation#{" for #{rule.inspect}" if rule}"
          return 1
        end
        selected.each do |name, text|
          puts "#{name}:"
          text.to_s.split("\n").each { |line| puts "  #{line}" }
        end
        0
      end

      def for_source_or_artifact
        file = @argv.shift
        artifact = artifact_for(file)
        yield artifact
      end

      def artifact_for(file)
        if file.end_with?(".json")
          Parsanol::PG::Artifact.load(file, tables_dir: @tables_dir || default_tables_dir(file))
        else
          artifact = compile_source(file)
          Parsanol::PG::Artifact.from_json(JSON.generate(artifact.envelope),
                                           tables_dir: @tables_dir || default_tables_dir(file))
        end
      end

      def compile_source(file)
        tables = @tables_dir || default_tables_dir(file)
        document = Parsanol::PG::Parser.new(File.read(file)).parse
        Parsanol::PG::Imports.merge!(document, [File.dirname(file)])
        Parsanol::PG::Compiler.compile(document, tables_dir: tables)
      end

      def default_artifact_name(source)
        "#{File.basename(source, '.pg')}.artifact.json"
      end

      # Batch mode: run a command over every *.pg in a directory.
      def batch(target)
        failures = {}
        Dir.glob(File.join(target, "*.pg")).sort.each do |file|
          result = yield artifact_for(file)
          failures[file] = result unless result.empty?
        end
        if failures.empty?
          puts "all flavors pass"
          0
        else
          failures.each { |file, list| list.each { |f| warn "#{file}: #{f}" } }
          1
        end
      end

      # Tables conventionally live in a "tables" directory beside the
      # grammar (as a sibling of the grammars directory).
      def default_tables_dir(file)
        dir = File.dirname(file)
        candidate = File.join(dir, "tables")
        candidate = File.join(File.dirname(dir), "tables") unless File.directory?(candidate)
        File.directory?(candidate) ? candidate : dir
      end

      def flag_value(flag)
        @argv.delete_at(@argv.index(flag) + 1).tap { @argv.delete(flag) } if @argv.include?(flag)
      end
    end
  end
end
