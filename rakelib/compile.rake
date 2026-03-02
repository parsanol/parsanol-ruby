# frozen_string_literal: true

require 'rb_sys/extensiontask'

RbSys::ExtensionTask.new('parsanol_native', GEMSPEC) do |ext|
  ext.lib_dir = 'lib/parsanol'
end
