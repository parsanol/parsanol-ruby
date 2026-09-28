# frozen_string_literal: true

require "parsanol"
require "json"

RSpec.describe Parsanol::PARG::Frontend do
  let(:base) { File.expand_path("../../../../../pubid/pubid-grammar", __dir__) }

  before do
    skip "pubid-grammar sibling checkout not available" unless Dir.exist?(File.join(base, "grammars"))
  end

  it "compiles to the identical envelope as the reference, for every flavor" do
    Dir.glob(File.join(base, "grammars", "*.parg")).sort.each do |file|
      source = File.read(file)
      reference = Parsanol::PARG::Parser.new(source).parse
      Parsanol::PARG::Imports.merge!(reference, [File.join(base, "grammars")])
      built = described_class.parse(source)
      Parsanol::PARG::Imports.merge!(built, [File.join(base, "grammars")])

      tables = File.join(base, "tables")
      ref_env = Parsanol::PARG::Compiler.compile(reference, tables_dir: tables).envelope
      built_env = Parsanol::PARG::Compiler.compile(built, tables_dir: tables).envelope

      expect(built_env["checksum"]).to eq(ref_env["checksum"])
    end
  end
end
