# frozen_string_literal: true

require 'rb_sys/extensiontask'

# Load gemspec directly if GEMSPEC constant is not defined
gemspec = defined?(GEMSPEC) ? GEMSPEC : Gem::Specification.load('parsanol.gemspec')

RbSys::ExtensionTask.new('parsanol_native', gemspec) do |ext|
  ext.lib_dir = 'lib/parsanol'
end
