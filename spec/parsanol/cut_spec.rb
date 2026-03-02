require 'spec_helper'

describe "Cut operator" do
  include Parsanol

  describe "basic functionality" do
    it "allows successful parse when cut succeeds" do
      parser = str('if').cut >> str(' ') >> str('x')
      result = parser.parse('if x')
      expect(result).to eq('if x')
    end

    it "provides cache eviction on successful cut" do
      # Cut operator primarily provides cache eviction for memory optimization
      # It clears cache before the cut position
      parser = str('if').cut >> str('x')
      result = parser.parse('ifx')
      expect(result).to eq('ifx')
    end
  end

  describe "with alternatives" do
    it "works with cuts in each alternative branch" do
      parser =
        (str('if').cut >> str(' then')) |
        (str('while').cut >> str(' do')) |
        str('print')

      expect(parser.parse('if then')).to eq('if then')
      expect(parser.parse('while do')).to eq('while do')
      expect(parser.parse('print')).to eq('print')
    end
  end

  describe "cut position" do
    it "cuts at the correct position" do
      parser = str('a').cut >> str('b') >> str('c')
      result = parser.parse('abc')
      expect(result).to eq('abc')
    end
  end

  describe "FIRST set delegation" do
    it "delegates first_set to wrapped parslet" do
      cut_atom = str('test').cut
      expect(cut_atom.first_set.size).to eq(1)
      expect(cut_atom.first_set.first).to be_a(Parsanol::Atoms::Str)
      expect(cut_atom.first_set.first.str).to eq('test')
    end
  end

  describe "caching behavior" do
    it "is not cached itself (thin wrapper)" do
      cut_atom = str('test').cut
      expect(cut_atom.cached?).to be false
    end
  end

  describe "string representation" do
    it "shows cut operator in to_s" do
      cut_atom = str('foo').cut
      expect(cut_atom.to_s).to include('foo')
      expect(cut_atom.to_s).to include('↑')
    end
  end
end
