# frozen_string_literal: true

# Seeded random PARG grammar + input generator for the cross-engine
# differential fuzzer (TODO.sota/8, Track A).
#
# Termination by construction: rules are generated right-to-left and may
# only reference later rules, so the rule graph is acyclic and has no left
# recursion. Every generated expression consumes at least one character, so
# no rule is nullable (no empty-branch lints, no zero-width repetition).
#
# The generator deliberately mixes the shapes that historically diverged:
# captures and uncaptured sequences, repetitions with finite bounds,
# maybe-nesting, ordered choice over disjoint literals, and lookahead guards.
module RandomGrammar
  ALPHABET = %w[a b c].freeze

  module_function

  def generate(seed:, count:)
    rng = Random.new(seed)
    Array.new(count) { |index| grammar(rng, index) }
  end

  def grammar(rng, index)
    rule_count = 3 + rng.rand(3)
    names = Array.new(rule_count) { |i| "r#{i}" }
    rules = {}
    (rule_count - 1).downto(0) do |i|
      later = names[(i + 1)..] || []
      rules[names[i]] = expr(rng, later, 0)
    end

    source = "grammar Fuzz#{index} version \"1.0.0\" {\n"
    rules.each { |name, node| source << "  #{name} = #{source_for(node)}\n" }
    source << "  entry main: #{names.first}\n}\n"
    { source: source, entry: "main", rules: rules, inputs: sample_inputs(rng, rules, names.first) }
  end

  def expr(rng, refs, depth)
    return leaf(rng) if depth >= 3

    roll = rng.rand
    if roll < 0.22
      leaf(rng)
    elsif roll < 0.38 && refs.any?
      { type: :ref, name: refs.sample(random: rng) }
    elsif roll < 0.56
      { type: :seq, items: Array.new(2 + rng.rand(2)) { expr(rng, refs, depth + 1) } }
    elsif roll < 0.70
      alternative(rng)
    elsif roll < 0.82
      min = 1 + rng.rand(2)
      { type: :rep, min: min, max: min + rng.rand(2), item: expr(rng, refs, depth + 1) }
    elsif roll < 0.90
      { type: :seq,
        items: [leaf(rng), { type: :opt, item: expr(rng, refs, depth + 1) }] }
    elsif roll < 0.96
      { type: :cap, name: "c#{rng.rand(4)}", item: expr(rng, refs, depth + 1) }
    else
      guard(rng)
    end
  end

  def leaf(rng)
    case rng.rand(3)
    when 0 then { type: :lit, text: ALPHABET.sample(random: rng), ci: false }
    when 1 then { type: :class, from: "a", to: "c" }
    else { type: :lit, text: ALPHABET.sample(random: rng), ci: true }
    end
  end

  def alternative(rng)
    branch_count = 2 + rng.rand(2)
    literals = ALPHABET.shuffle(random: rng).first(branch_count)
    { type: :alt, items: literals.map { |text| { type: :lit, text: text, ci: false } } }
  end

  def guard(rng)
    kind = rng.rand(2).zero? ? :and : :not
    literal = kind == :and ? "a" : "z"
    { type: :guard, kind: kind, lit: literal, item: { type: :class, from: "a", to: "c" } }
  end

  def source_for(node)
    case node[:type]
    when :lit then node[:ci] ? "%i\"#{node[:text]}\"" : "\"#{node[:text]}\""
    when :class then "%x#{format('%02X', node[:from].ord)}-#{format('%02X', node[:to].ord)}"
    when :ref then node[:name]
    when :seq then "( #{node[:items].map { |item| source_for(item) }.join(' ')} )"
    when :alt then "( #{node[:items].map { |item| source_for(item) }.join(' / ')} )"
    when :rep then "#{node[:min]}*#{node[:max]}( #{source_for(node[:item])} )"
    when :opt then "[ #{source_for(node[:item])} ]"
    when :cap then "( #{source_for(node[:item])} ) as #{node[:name]}"
    when :guard
      "#{node[:kind] == :and ? '&' : '!'}\"#{node[:lit]}\" #{source_for(node[:item])}"
    else
      raise ArgumentError, "unknown fuzz node #{node[:type].inspect}"
    end
  end

  def sample_inputs(rng, rules, root)
    inputs = []
    6.times do
      text = derive(rules[root], rules, rng, 0)
      inputs << text
      inputs << mutate(text, rng) if rng.rand < 0.6
    end
    inputs.push("", "z", "zz", "abcabc")
    inputs.uniq
  end

  def derive(node, rules, rng, depth)
    return "" if depth > 40

    case node[:type]
    when :lit then node[:ci] ? node[:text].downcase : node[:text]
    when :class then rng.rand((node[:from].ord)..(node[:to].ord)).chr
    when :ref then derive(rules[node[:name]], rules, rng, depth + 1)
    when :seq then node[:items].map { |item| derive(item, rules, rng, depth + 1) }.join
    when :alt then derive(node[:items].sample(random: rng), rules, rng, depth + 1)
    when :rep
      count = node[:min] + rng.rand(node[:max] - node[:min] + 1)
      Array.new([count, 4].min) { derive(node[:item], rules, rng, depth + 1) }.join
    when :opt then rng.rand(2).zero? ? "" : derive(node[:item], rules, rng, depth + 1)
    when :cap then derive(node[:item], rules, rng, depth + 1)
    when :guard
      text = derive(node[:item], rules, rng, depth + 1)
      if node[:kind] == :and
        node[:lit] + text[1..].to_s
      else
        text.start_with?(node[:lit]) ? "b#{text[1..]}" : text
      end
    else
      ""
    end
  end

  def mutate(text, rng)
    chars = text.chars
    case rng.rand(3)
    when 0
      chars.delete_at(rng.rand(chars.length)) unless chars.empty?
    when 1
      chars.insert(rng.rand(chars.length + 1), (ALPHABET + %w[z A]).sample(random: rng))
    else
      chars[rng.rand(chars.length)] = (ALPHABET + %w[z]).sample(random: rng) unless chars.empty?
    end
    chars.join
  end
end
