# frozen_string_literal: true

# Steepfile for RBS type checking

target :lib do
  signature "sig"

  check "lib/parsanol.rb"
  check "lib/parsanol/atoms/base.rb"
  check "lib/parsanol/atoms/str.rb"
  check "lib/parsanol/atoms/re.rb"
  check "lib/parsanol/atoms/sequence.rb"
  check "lib/parsanol/atoms/alternative.rb"
  check "lib/parsanol/atoms/repetition.rb"
  check "lib/parsanol/atoms/named.rb"
  check "lib/parsanol/atoms/entity.rb"
  check "lib/parsanol/atoms/lookahead.rb"
  check "lib/parsanol/atoms/capture.rb"
  check "lib/parsanol/atoms/scope.rb"
  check "lib/parsanol/atoms/dynamic.rb"
  check "lib/parsanol/atoms/infix.rb"
  check "lib/parsanol/atoms/cut.rb"
  check "lib/parsanol/atoms/ignored.rb"
  check "lib/parsanol/atoms/can_flatten.rb"
  check "lib/parsanol/atoms/dsl.rb"
  check "lib/parsanol/atoms/visitor.rb"
  check "lib/parsanol/atoms/context.rb"

  check "lib/parsanol/parser.rb"
  check "lib/parsanol/transform.rb"
  check "lib/parsanol/pattern.rb"
  check "lib/parsanol/pattern/binding.rb"
  check "lib/parsanol/cause.rb"
  check "lib/parsanol/source.rb"
  check "lib/parsanol/slice.rb"
  check "lib/parsanol/context.rb"
  check "lib/parsanol/scope.rb"
  check "lib/parsanol/convenience.rb"

  check "lib/parsanol/error_reporter.rb"
  check "lib/parsanol/error_reporter/contextual.rb"
  check "lib/parsanol/error_reporter/deepest.rb"
  check "lib/parsanol/error_reporter/tree.rb"

  check "lib/parsanol/source/line_cache.rb"

  check "lib/parsanol/expression.rb"
  check "lib/parsanol/expression/treetop.rb"

  # Skip native extension (Rust)
  ignore "lib/parsanol/parsanol_native.bundle"
  ignore "lib/parsanol/native.rb"
  ignore "lib/parsanol/native/"
end

target :spec do
  signature "sig"

  check "spec/"
end
