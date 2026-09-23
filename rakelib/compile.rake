# frozen_string_literal: true

require "rb_sys/extensiontask"

# Load gemspec directly if GEMSPEC constant is not defined
gemspec = defined?(GEMSPEC) ? GEMSPEC : Gem::Specification.load("parsanol.gemspec")

RbSys::ExtensionTask.new("parsanol_native", gemspec) do |ext|
  ext.lib_dir = "lib/parsanol"

  # rake-compiler packages cross gems from tmp/<platform>/stage/, so the
  # vendored cdylib must land THERE — the canonical hook is the platform
  # spec itself. Env-gated (cross-gem jobs only).
  ext.cross_compiling do |spec|
    next unless ENV["PARSANOL_VENDOR_CDYLIB"] == "1"

    triple = ENV.fetch("RUST_TARGET", nil)
    args = ["cargo", "build", "--release", "-p", "parsanol_cdylib"]
    args += ["--target", triple] if triple
    sh(*args)
    dir = triple ? "target/#{triple}/release" : "target/release"
    name = %w[libparsanol.so libparsanol.dylib parsanol.dll]
      .map { |n| File.join(dir, n) }
      .find { |f| File.file?(f) }
    raise "cdylib not found under #{dir}" unless name

    stage_lib = File.join("tmp", spec.platform.to_s, "stage", "lib", "parsanol", "native")
    mkdir_p stage_lib
    cp name, stage_lib
    spec.files += ["lib/parsanol/native/#{File.basename(name)}"]
  end
end

# Cross-gem builds run `rake gem` inside rb-sys-dock (see
# .github/workflows/gem-build.yml). Task declarations are additive in
# rake, so this prerequisite attaches regardless of when rb-sys defines
# the cross `gem` task. Env-gated so local/plain builds never vendor.
if ENV["PARSANOL_VENDOR_CDYLIB"] == "1"
  task "gem" => "gem:vendor_cdylib"
end
