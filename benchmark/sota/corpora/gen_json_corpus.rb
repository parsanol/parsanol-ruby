# Deterministic JSON corpus generator: valid documents at documented
# sizes. Seeded so every harness parses byte-identical inputs.
require "json"

srand(20261020)

def rand_string(_depth)
  chars = ("a".."z").to_a + ("0".."9").to_a + [" ", "_", "é", "中"]
  len = rand(4..40)
  Array.new(len) { chars.sample }.join
end

def rand_value(depth)
  case rand(depth > 3 ? 3 : 6)
  when 0, 1 then rand_string(depth)
  when 2 then rand(2).zero?
  when 3 then rand(-5000..4999)
  when 4 then rand < 0.5 ? nil : (rand * 100).round(4)
  else build_object(depth + 1)
  end
end

def build_object(depth)
  keys = Array.new(rand(3..8)) { rand_string(depth).delete(' "\\\\') }.uniq
  keys.to_h { |k| [k, rand_value(depth)] }
end

def build_array(depth)
  Array.new(rand(5..15)) { rand_value(depth) }
end

docs = {
  "small" => build_object(1),
  "medium" => { "items" => build_array(2), "meta" => build_object(2) },
  "large" => Array.new(200) { build_object(3) },
  "wide" => build_object(4).merge("data" => Array.new(500) { rand(10_000) }),
}

File.write("corpora/json_inputs.json",
           JSON.generate(docs.transform_values { |d| JSON.generate(d) }))
puts "json_inputs.json: #{docs.map { |k, v| "#{k}=#{JSON.generate(v).bytesize}B" }.join(', ')}"
