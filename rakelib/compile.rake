# frozen_string_literal: true

require "rb_sys/extensiontask"

# Load gemspec directly if GEMSPEC constant is not defined
gemspec = defined?(GEMSPEC) ? GEMSPEC : Gem::Specification.load("parsanol.gemspec")

RbSys::ExtensionTask.new("parsanol_native", gemspec) do |ext|
  ext.lib_dir = "lib/parsanol"
end

# Cross-gem builds run `rake gem` inside rb-sys-dock (see
# .github/workflows/gem-build.yml). Task declarations are additive in
# rake, so this prerequisite attaches regardless of when rb-sys defines
# the cross `gem` task. Env-gated so local/plain builds never vendor.
if ENV["PARSANOL_VENDOR_CDYLIB"] == "1"
  task "gem" => "gem:vendor_cdylib"
end
