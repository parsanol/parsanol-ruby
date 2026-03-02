# ISO 8601 Date/Time Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/iso-8601
ruby basic.rb
```

## Code Walkthrough

### Calendar Date Rule

Standard YYYY-MM-DD format with optional separators:

```ruby
rule(:calendar_date) {
  year >> date_separator >> month >> date_separator >> day
}

rule(:date_separator) { str('-').maybe }
```

The `.maybe` on the separator allows both `2024-01-15` and `20240115`.

### Week Date Rule

Year, week number, and weekday:

```ruby
rule(:week_date) {
  year >> str('-W') >>
  match('[0-9]').repeat(2, 2).as(:week) >>
  str('-') >>
  match('[1-7]').as(:weekday)
}
```

Weekday is 1-7 (Monday to Sunday), per ISO 8601.

### Ordinal Date Rule

Year and day-of-year:

```ruby
rule(:ordinal_date) {
  year >> str('-') >>
  match('[0-9]').repeat(3, 3).as(:ordinal_day)
}
```

Three-digit day number (001-366).

### Time Rule

Hours, minutes, seconds with optional fraction:

```ruby
rule(:time_basic) {
  hour >> time_separator >> minute >> time_separator >> second >> fraction.maybe
}

rule(:fraction) { str('.') >> match('[0-9]').repeat(1).as(:fraction) }
```

Fraction supports arbitrary precision subseconds.

### Timezone Rules

UTC designator or offset:

```ruby
rule(:utc_designator) { str('Z').as(:utc) }

rule(:tz_offset) {
  tz_sign >> tz_hour >> tz_minute
}

rule(:timezone) { utc_designator | tz_offset | str('') }
```

Empty string allows local time without timezone.

### DateTime Combination

Date and time joined by `T`:

```ruby
rule(:datetime) {
  (calendar_date | week_date | ordinal_date) >>
  (str('T') | str(' ')) >>
  time
}
```

Space separator is allowed by some implementations.

### Duration Rule

P[nY][nM][nD][T[nH][nM][nS]] format:

```ruby
rule(:duration) {
  str('P') >>
  (
    (match('[0-9]').repeat(1).as(:years) >> str('Y')).maybe >>
    (match('[0-9]').repeat(1).as(:months) >> str('M')).maybe >>
    (match('[0-9]').repeat(1).as(:days) >> str('D')).maybe >>
    (str('T') >> (...)).maybe
  )
}
```

Every component is optional; at least one is required.

## Output Types

```ruby
# Calendar date
IsoDate.new("2024", "01", "15", nil, nil, nil)
# to_s => "2024-01-15"

# Time with timezone
IsoTime.new("10", "30", "00", nil, "Z", nil, nil)
# to_s => "10:30:00Z"

# Duration
IsoDuration.new("1", "2", "3", "4", "5", "6")
# to_s => "P1Y2M3DT4H5M6S"
# to_seconds => 36993906
```

## Design Decisions

### Why Separate Date/Time/Duration Classes?

Each ISO 8601 type has distinct fields and semantics. Separate classes provide type safety and appropriate methods.

### Why Maybe on Separators?

ISO 8601 allows both basic (no separators) and extended (with separators) formats. The grammar handles both.

### Why Empty String in Timezone Alternative?

Local time without timezone is valid ISO 8601. The empty string matches when neither Z nor offset is present.

### Why to_seconds for Duration?

Duration calculations often need total seconds. The method approximates using average month/year lengths.
