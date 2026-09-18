# frozen_string_literal: true

require "rubygems/package"

# Builds the lib-only x64-mingw32 platform stub (see release.yml for
# why a native legacy-MinGW gem cannot exist for this gem's Ruby floor).
spec = Gem::Specification.load("parsanol.gemspec")
spec.platform = Gem::Platform.new("x64-mingw32")
spec.extensions = []
spec.files = spec.files.reject { |f| f.start_with?("ext/") }
Gem::Package.build(spec)
