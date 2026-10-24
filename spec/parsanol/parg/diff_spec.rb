# frozen_string_literal: true

require "parsanol"
require "json"

# ruby#306: `parg diff` classifies grammar changes against the artifact
# contract. Canonical rendering means compiler-version churn and key
# order never read as a change; ambiguous cases land high with evidence.
RSpec.describe "PARG diff" do
  def envelope_for(source)
    document = Parsanol::PARG::Parser.new(source).parse
    JSON.generate(Parsanol::PARG::Compiler.compile(document).envelope)
  end

  def diff_levels(old_source, new_source)
    findings = Parsanol::PARG::Diff.diff(
      JSON.parse(envelope_for(old_source)),
      JSON.parse(envelope_for(new_source)),
    )
    [Parsanol::PARG::Diff.level(findings), findings]
  end

  def base_grammar
    <<~PARG
      grammar Base version "1.0.0" {
        word = 1*( ALPHA )
        pair = word "=" word
        entry document: pair
        test document {
          accept "a=b"
        }
      }
    PARG
  end

  it "reports no semantic change when only the compiler re-compiles" do
    expect(diff_levels(base_grammar, base_grammar)).to eq([:none, []])
  end

  it "classifies a literal fix as patch" do
    new_source = base_grammar.sub('word "=" word', 'word ":" word')
      .sub('accept "a=b"', 'accept "a:b"')
    level, findings = diff_levels(base_grammar, new_source)
    expect(level).to eq(:patch)
    expect(findings.map(&:kind)).to include(:literal_or_bound_change)
  end

  it "classifies an added alternative branch as minor" do
    new_source = base_grammar.sub('pair = word "=" word', 'pair = word "=" word / word "-" word')
      .sub('accept "a=b"', "accept \"a=b\"\n    accept \"a-b\"")
    level, _findings = diff_levels(base_grammar, new_source)
    expect(level).to eq(:minor)
  end

  it "classifies a removed alternative branch as major" do
    two_branches = base_grammar.sub(
      'pair = word "=" word',
      'pair = word "=" word / word "-" word',
    ).sub('accept "a=b"', "accept \"a=b\"\n    accept \"a-b\"")
    level, findings = diff_levels(two_branches, base_grammar)
    expect(level).to eq(:major)
    expect(findings.map(&:kind)).to include(:branch_removed)
  end

  it "classifies an added capture as minor" do
    new_source = base_grammar.sub('pair = word "=" word', 'pair = word as left "=" word')
    level, _findings = diff_levels(base_grammar, new_source)
    expect(level).to eq(:minor)
  end

  it "classifies a removed capture as major" do
    captured = base_grammar.sub('pair = word "=" word', 'pair = word as left "=" word')
    new_source = captured.sub(" as left", "")
    level, findings = diff_levels(captured, new_source)
    expect(level).to eq(:major)
    expect(findings.map(&:kind)).to include(:capture_removed)
  end

  it "classifies an added entry as minor and a removed entry as major" do
    with_second = base_grammar.sub(
      "entry document: pair",
      "entry document: pair\n  entry second: word",
    )
    expect(diff_levels(base_grammar, with_second).first).to eq(:minor)
    expect(diff_levels(with_second, base_grammar).first).to eq(:major)
  end

  it "classifies added tests as patch" do
    new_source = base_grammar.sub('accept "a=b"', "accept \"a=b\"\n    accept \"c=d\"")
    level, findings = diff_levels(base_grammar, new_source)
    expect(level).to eq(:patch)
    expect(findings.map(&:kind)).to include(:tests_added)
  end

  it "classifies removed tests as major (the contract weakened)" do
    more_tests = base_grammar.sub('accept "a=b"', "accept \"a=b\"\n    reject \"a\"")
    level, findings = diff_levels(more_tests, base_grammar)
    expect(level).to eq(:major)
    expect(findings.map(&:kind)).to include(:tests_removed)
  end

  it "suggests the bump level" do
    findings = Parsanol::PARG::Diff.diff(
      JSON.parse(envelope_for(base_grammar)),
      JSON.parse(envelope_for(base_grammar)),
    )
    expect(Parsanol::PARG::Diff.suggest_bump(findings)).to eq("no bump needed")
  end
end
