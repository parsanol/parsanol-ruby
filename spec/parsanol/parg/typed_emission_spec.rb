# frozen_string_literal: true

require "parsanol"
require "parsanol/parg"
require "json"

RSpec.describe "typed emission (ruby#308 v2)" do
  def artifact(name = "bindings_array")
    dir = ENV.fetch("PARG_CONFORMANCE_DIR", nil)
    path = dir || File.expand_path("../../../parsanol-rs/corpus/conformance", __dir__)
    unless dir || File.directory?(path)
      skip "conformance corpus not present (set PARG_CONFORMANCE_DIR)"
    end
    Parsanol::PARG::Artifact.from_json(File.read(File.join(path, "#{name}.json")))
  end

  def schema_for(name = "bindings_array")
    Parsanol::PARG::Schema.from_artifact(artifact(name))
  end

  describe "the bound model shape" do
    it "derives array-of-object nesting from the binding paths" do
      shape = Parsanol::PARG::Schema.shape({ "items[].n" => { "type" => "integer", "card" => "1" } })
      expect(shape).to eq(
        "items" => {
          "kind" => "array",
          "of" => { "n" => { "kind" => "leaf", "type" => "integer", "card" => "1" } },
        },
      )
    end

    it "derives dot nesting and array-of-leaf forms" do
      shape = Parsanol::PARG::Schema.shape(
        "a.b" => { "type" => "string", "card" => "1" },
        "tags[]" => { "type" => "string", "card" => "1" },
        "year" => { "type" => "integer", "card" => "0..1" },
      )
      expect(shape.dig("a", "b", "kind")).to eq("leaf")
      expect(shape.dig("tags", "kind")).to eq("array")
      expect(shape.dig("tags", "of", "kind")).to eq("leaf")
      expect(shape.dig("year", "card")).to eq("0..1")
    end
  end

  describe "the emitters" do
    it "emits nested lutaml-model classes" do
      ruby = Parsanol::PARG::Schema.to_ruby(schema_for)
      expect(ruby).to include('require "lutaml/model"')
      expect(ruby).to include("class Main < Lutaml::Model::Serializable")
      expect(ruby).to include("attribute :items, MainItems, collection: true")
      expect(ruby).to include("class MainItems < Lutaml::Model::Serializable")
      expect(ruby).to include("attribute :n, :integer")
      expect(ruby.scan(/^end$/).length).to eq(2)
    end

    it "emits nested serde structs" do
      rust = Parsanol::PARG::Schema.to_rust(schema_for)
      expect(rust).to include("pub struct Main {")
      expect(rust).to include("pub items: Vec<MainItems>,")
      expect(rust).to include("pub struct MainItems {")
      expect(rust).to include("pub n: i64,")
    end

    it "emits nested interfaces" do
      ts = Parsanol::PARG::Schema.to_typescript(schema_for)
      expect(ts).to include("export interface Main {")
      expect(ts).to include("items: MainItems[];")
      expect(ts).to include("export interface MainItems {")
      expect(ts).to include("n: number;")
    end
  end

  describe "the generated models materialize the bound output" do
    it "round-trips a bound hash through the emitted lutaml-model class" do
      ruby = Parsanol::PARG::Schema.to_ruby(schema_for)
      Object.class_eval(ruby) # rubocop:disable Security/Eval -- generated from the checked-in fixture
      bound = artifact.envelope["tests"].first.fetch("expect")
      model = Main.new(bound)
      expect(model.items.map(&:n)).to eq([1, 2])
    end
  end
end
