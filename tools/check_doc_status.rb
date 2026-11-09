# frozen_string_literal: true

# ruby#459: the feature-status convention linter. Fails when a status
# line uses an unknown form, or when a "Specified"/"tracked in"
# mention carries neither a shipped version nor an issue/PR tracking
# number — the guide cannot silently lag the compiler.
#
#   ruby tools/check_doc_status.rb          # checks docs/*.md
#   rake docs:status                        # same, via rake

DOCS = ARGV.empty? ? Dir[File.join(__dir__, "..", "docs", "*.md")] : ARGV

STATUSES = /\Astatus:\s*(shipped|partial|specified|roadmap)\b/
SHIPPED_VERSION = /\Astatus:\s*shipped(\s*\(\d+\.\d+(\.\d+)?\))?\s*(--.*)?\z/
TRACKING = /#\d+|parsanol-ruby|parsanol-rs/

failures = []

DOCS.sort.each do |path|
  fence = false
  File.readlines(path).each_with_index do |line, i|
    number = i + 1
    text = line.chomp

    fence = !fence if text.start_with?("```")
    next if fence

    # The status convention itself: a status line must start the line
    # and carry one of the four known forms.
    if text.strip.start_with?("status:")
      failures << "#{path}:#{number}: unknown status form: #{text.strip}" unless STATUSES.match?(text.strip)
      next
    end

    # A stale spec annotation is an ITALIC note ("*Specified …*" / "*…
    # implementation tracked in …*") that names no tracking number and
    # no shipped version — the shape the guide drifted into.
    next unless text.match?(/\*.*Specified.*\*|implementation tracked in/)

    failures << "#{path}:#{number}: stale spec annotation without a status line or tracking number: #{text.strip[0, 80]}"
  end
end

if failures.empty?
  puts "doc status: #{DOCS.size} files clean"
else
  warn failures.join("\n")
  abort "#{failures.size} doc-status failure(s)"
end
