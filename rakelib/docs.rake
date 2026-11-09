# frozen_string_literal: true

require "rake"

namespace :lint do
  desc "Enforce the feature-status convention in the docs (#459)"
  task :docs do
    docs = %w[docs/parg-language-guide.md docs/parg-semantics.md]
    # `status: shipped (1.3.131)` / `partial (…)` / `specified (not
    # implemented)` / `roadmap`, optionally followed by prose.
    status_re = /\Astatus: (shipped \(\d+\.\d+\.\d+\)|partial \([^)]+\)|specified \(not implemented\)|roadmap\))( .*)?\z/
    # Legacy phrasing the convention replaced: a "tracked in"/"Specified"
    # mention must carry an issue reference on the same line, or it is
    # exactly the silent staleness the status lines exist to prevent.
    stale_re = /(\bSpecified \d{4}|\btracked in(?!.*#\d))/

    failures = []

    docs.each do |path|
      File.readlines(path).each_with_index do |raw, i|
        line = raw.chomp
        plain = line.lstrip
        if plain.start_with?("status:")
          failures << "#{path}:#{i + 1}: bad status shape: #{line.strip[0, 72]}" unless status_re.match?(line.strip)
        elsif stale_re.match?(line) && !plain.start_with?("- `status:") # the convention's own examples
          failures << "#{path}:#{i + 1}: stale phrasing (use a status line): #{line.strip[0, 72]}"
        end
      end
    end

    if failures.empty?
      puts "lint:docs OK (#{docs.join(', ')})"
    else
      warn failures.join("\n")
      raise "lint:docs found #{failures.length} problem(s)"
    end
  end
end
