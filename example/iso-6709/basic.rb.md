# ISO 6709 Geographic Coordinate Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/iso-6709
ruby basic.rb
```

## Code Walkthrough

### Sign Convention

Latitude and longitude use signed notation:

```ruby
rule(:lat_sign) { (str('+') | str('-')).as(:lat_sign) }
rule(:lon_sign) { (str('+') | str('-')).as(:lon_sign) }
```

Positive (+) means North/East; negative (-) means South/West.

### Decimal Degrees

Simple decimal format captures degrees and optional fraction:

```ruby
rule(:decimal_deg) {
  match('[0-9]').repeat(1, 2).as(:degrees) >>
  (str('.') >> match('[0-9]').repeat(1)).maybe.as(:fraction)
}
```

Latitude uses 1-2 digits (0-90); longitude uses 1-3 digits (0-180).

### Sexagesimal (DMS) Format

Degrees, minutes, and seconds with optional fractions:

```ruby
rule(:sexagesimal) {
  match('[0-9]').repeat(1, 2).as(:degrees) >>
  (
    space >>
    match('[0-9]').repeat(1, 2).as(:minutes) >>
    (
      space >>
      match('[0-9]').repeat(1, 2).as(:seconds) >>
      (str('.') >> match('[0-9]').repeat(1)).maybe.as(:sec_fraction)
    ).maybe
  ).maybe
}
```

Each component is optional, supporting `DD`, `DD MM`, or `DD MM SS.ss`.

### Latitude and Longitude Rules

Latitude is limited to ±90°:

```ruby
rule(:latitude) {
  lat_sign >> (decimal_deg | sexagesimal).as(:latitude)
}
```

Longitude extends to ±180°:

```ruby
rule(:longitude) {
  lon_sign >> (decimal_deg_3 | sexagesimal_3).as(:longitude)
}
```

### Altitude (Optional)

Altitude in meters with sign:

```ruby
rule(:altitude) {
  (str('+') | str('-')).as(:alt_sign) >>
  match('[0-9]').repeat(1).as(:alt_value) >>
  (str('.') >> match('[0-9]').repeat(1)).maybe.as(:alt_fraction)
}
```

Positive is above sea level; negative is below.

### Coordinate Reference System

CRS specifies the reference system:

```ruby
rule(:crs) {
  str('CRS') >>
  match('[A-Z0-9_]').repeat(1).as(:crs) >>
  str('/')
}
```

Common values: `WGS_84`, `NAD83`.

### Complete Coordinate

All components assembled:

```ruby
rule(:coordinate) {
  latitude >>
  (space | str('')).maybe >>
  longitude >>
  altitude.maybe.as(:altitude) >>
  (str('/') >> crs).maybe.as(:crs_info)
}
```

Altitude and CRS are optional.

## Output Types

```ruby
# Decimal degrees
Coordinate.new("+", {:degrees=>"40", :fraction=>".6894"}, "-", {:degrees=>"074", :fraction=>".0447"}, nil, nil)
# to_h => {:latitude=>40.6894, :longitude=>-74.0447}

# With altitude and CRS
Coordinate.new("+", lat_hash, "+", lon_hash, {:alt_sign=>"+", :alt_value=>"330"}, "WGS_84")
# to_h => {:latitude=>48.8584, :longitude=>2.2945, :altitude=>330.0, :crs=>"WGS_84"}
```

## Design Decisions

### Why Separate Latitude/Longitude Rules?

Different valid ranges (±90 vs ±180) require different digit constraints. Separate rules enforce format correctness.

### Why Struct with to_h?

Struct provides clean attribute access while `to_h` gives a simple hash representation for serialization.

### Why Maybe for Optional Components?

ISO 6709 allows coordinates without altitude or CRS. Using `.maybe` keeps the grammar flexible while still capturing data when present.
