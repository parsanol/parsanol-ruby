# frozen_string_literal: true

require "rb_sys/extensiontask"

# Load gemspec directly if GEMSPEC constant is not defined
gemspec = defined?(GEMSPEC) ? GEMSPEC : Gem::Specification.load("parsanol.gemspec")

RbSys::ExtensionTask.new("parsanol_native", gemspec) do |ext|
  ext.lib_dir = "lib/parsanol"

  # Vendor the pure-portable cdylib into platform gems (TODO.perf/9).
  # rake-compiler auto-stages callback-added files from the project
  # tree (define_staging_file_tasks), so the only job here is declaring
  # the file — the cross-gem jobs' pre-setup-command builds it into the
  # tree first. Platform-driven, not env-driven: the dock container
  # does not inherit the job env.
  ext.cross_compiling do |spec|
    next if spec.platform == Gem::Platform::RUBY

    vendored = Dir["lib/parsanol/native/libparsanol.{so,dylib,dll}"]
    if vendored.empty?
      raise "platform gem #{spec.platform} has no vendored cdylib — " \
            "run `rake gem:vendor_cdylib` (or the workflow pre-setup-command) first"
    end

    spec.files += vendored
  end
end

# Cross-gem builds run `rake gem` inside rb-sys-dock (see
# .github/workflows/gem-build.yml). Task declarations are additive in
# rake, so this prerequisite attaches regardless of when rb-sys defines
# the cross `gem` task. Env-gated so local/plain builds never vendor.
if ENV["PARSANOL_VENDOR_CDYLIB"] == "1"
  task "gem" => "gem:vendor_cdylib"
end
