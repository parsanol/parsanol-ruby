# frozen_string_literal: true

# ISO 8601 Date/Time Parser - Ruby Implementation
#
# Parse ISO 8601 dates, times, datetimes, and durations.
#
# Run with: ruby example/iso-8601/basic.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "parsanol/parslet"

# ISO 8601 parser
class Iso8601Parser < Parsanol::Parser
  root :iso_value

  # Date components
  rule(:year) { match("[0-9]").repeat(4, 4).as(:year) }
  rule(:month) { match("[0-9]").repeat(2, 2).as(:month) }
  rule(:day) { match("[0-9]").repeat(2, 2).as(:day) }
  rule(:date_separator) { str("-").maybe }

  # Calendar date: YYYY-MM-DD or YYYYMMDD
  rule(:calendar_date) do
    year >> date_separator >> month >> date_separator >> day
  end

  # Week date: YYYY-Www-D
  rule(:week_date) do
    year >> str("-W") >>
      match("[0-9]").repeat(2, 2).as(:week) >>
      str("-") >>
      match("[1-7]").as(:weekday)
  end

  # Ordinal date: YYYY-DDD
  rule(:ordinal_date) do
    year >> str("-") >>
      match("[0-9]").repeat(3, 3).as(:ordinal_day)
  end

  # Time components
  rule(:hour) { match("[0-9]").repeat(2, 2).as(:hour) }
  rule(:minute) { match("[0-9]").repeat(2, 2).as(:minute) }
  rule(:second) { match("[0-9]").repeat(2, 2).as(:second) }
  rule(:fraction) { str(".") >> match("[0-9]").repeat(1).as(:fraction) }
  rule(:time_separator) { str(":").maybe }

  # Time: HH:MM:SS[.frac]
  rule(:time_basic) do
    hour >> time_separator >> minute >> time_separator >> second >> fraction.maybe
  end

  # Timezone
  rule(:utc_designator) { str("Z").as(:utc) }
  rule(:tz_sign) { (str("+") | str("-")).as(:tz_sign) }
  rule(:tz_hour) { match("[0-9]").repeat(2, 2).as(:tz_hour) }
  rule(:tz_minute) do
    (str(":") >> match("[0-9]").repeat(2, 2)).maybe.as(:tz_minute)
  end

  rule(:tz_offset) do
    tz_sign >> tz_hour >> tz_minute
  end

  rule(:timezone) { utc_designator | tz_offset | str("") }

  rule(:time) { time_basic >> timezone }

  # Combined date-time
  rule(:datetime) do
    (calendar_date | week_date | ordinal_date) >>
      (str("T") | str(" ")) >>
      time
  end

  # Duration: P[nY][nM][nD][T[nH][nM][nS]]
  rule(:duration) do
    str("P") >>
      (
        (match("[0-9]").repeat(1).as(:years) >> str("Y")).maybe >>
        (match("[0-9]").repeat(1).as(:months) >> str("M")).maybe >>
        (match("[0-9]").repeat(1).as(:days) >> str("D")).maybe >>
        (
          str("T") >>
          (
            (match("[0-9]").repeat(1).as(:hours) >> str("H")).maybe >>
            (match("[0-9]").repeat(1).as(:minutes) >> str("M")).maybe >>
            (match("[0-9]").repeat(1).as(:seconds) >> str("S")).maybe
          )
        ).maybe
      )
  end

  # Top-level alternatives
  rule(:iso_value) { datetime | calendar_date | time | duration }
end

# Date result class
IsoDate = Struct.new(:year, :month, :day, :week, :weekday, :ordinal_day) do
  def to_s
    if week
      "#{year}-W#{week}-#{weekday}"
    elsif ordinal_day
      "#{year}-#{ordinal_day}"
    else
      "#{year}-#{month}-#{day}"
    end
  end

  def to_date
    require "date"
    if week
      Date.commercial(year.to_i, week.to_i, weekday.to_i)
    elsif ordinal_day
      Date.ordinal(year.to_i, ordinal_day.to_i)
    else
      Date.new(year.to_i, month.to_i, day.to_i)
    end
  end
end

# Time result class
IsoTime = Struct.new(:hour, :minute, :second, :fraction, :utc, :tz_sign,
                     :tz_hour, :tz_minute) do
  def to_s
    h = "#{hour}:#{minute}:#{second}"
    h += ".#{fraction}" if fraction
    h += "Z" if utc
    h += "#{tz_sign}#{tz_hour}#{tz_minute}" if tz_hour
    h
  end
end

# DateTime result class
IsoDateTime = Struct.new(:date, :time) do
  def to_s
    "#{date}T#{time}"
  end
end

# Duration result class
IsoDuration = Struct.new(:years, :months, :days, :hours, :minutes, :seconds) do
  def to_s
    parts = ["P"]
    parts << "#{years}Y" if years
    parts << "#{months}M" if months
    parts << "#{days}D" if days

    time_parts = []
    time_parts << "#{hours}H" if hours
    time_parts << "#{minutes}M" if minutes
    time_parts << "#{seconds}S" if seconds

    if time_parts.any?
      parts << "T"
      parts.concat(time_parts)
    end

    parts.join
  end

  def to_seconds
    total = 0
    total += years.to_i * 365.25 * 24 * 3600 if years
    total += months.to_i * 30.44 * 24 * 3600 if months
    total += days.to_i * 24 * 3600 if days
    total += hours.to_i * 3600 if hours
    total += minutes.to_i * 60 if minutes
    total += seconds.to_i if seconds
    total.to_i
  end
end

# Transform parse tree to result objects
class Iso8601Transform < Parsanol::Transform
  # Calendar date
  rule(year: simple(:y), month: simple(:m), day: simple(:d)) do
    IsoDate.new(y.to_s, m.to_s, d.to_s, nil, nil, nil)
  end

  # Week date
  rule(year: simple(:y), week: simple(:w), weekday: simple(:wd)) do
    IsoDate.new(y.to_s, nil, nil, w.to_s, wd.to_s, nil)
  end

  # Ordinal date
  rule(year: simple(:y), ordinal_day: simple(:od)) do
    IsoDate.new(y.to_s, nil, nil, nil, nil, od.to_s)
  end

  # Time
  rule(hour: simple(:h), minute: simple(:m), second: simple(:s)) do
    IsoTime.new(h.to_s, m.to_s, s.to_s, nil, nil, nil, nil)
  end

  rule(hour: simple(:h), minute: simple(:m), second: simple(:s),
       fraction: simple(:f)) do
    IsoTime.new(h.to_s, m.to_s, s.to_s, f.to_s, nil, nil, nil)
  end

  rule(hour: simple(:h), minute: simple(:m), second: simple(:s),
       utc: simple(:u)) do
    IsoTime.new(h.to_s, m.to_s, s.to_s, nil, u.to_s, nil, nil)
  end

  rule(hour: simple(:h), minute: simple(:m), second: simple(:s),
       tz_sign: simple(:ts), tz_hour: simple(:th)) do
    IsoTime.new(h.to_s, m.to_s, s.to_s, nil, nil, ts.to_s, th.to_s, nil)
  end

  # Duration
  rule(
    years: simple(:y), months: simple(:mo), days: simple(:d),
    hours: simple(:h), minutes: simple(:mi), seconds: simple(:s)
  ) do
    IsoDuration.new(y.to_s, mo.to_s, d.to_s, h.to_s, mi.to_s, s.to_s)
  end
end

# Parse ISO 8601 string
def parse_iso8601(str)
  parser = Iso8601Parser.new
  transform = Iso8601Transform.new

  tree = parser.parse(str)
  transform.apply(tree)
rescue Parsanol::ParseError => e
  puts "Parse error: #{e.message}"
  nil
end

# Main demo
if __FILE__ == $PROGRAM_NAME
  puts "ISO 8601 Date/Time Parser"
  puts "=" * 50
  puts

  examples = [
    # Calendar dates
    ["2024-01-15", "Calendar date"],
    ["20240115", "Compact date"],
    ["2024-12-25", "Christmas"],

    # Week dates
    ["2024-W02-1", "Week date (2nd week, Monday)"],

    # Ordinal dates
    ["2024-015", "Ordinal date (15th day)"],

    # Times
    ["10:30:00", "Time"],
    ["10:30:00.123", "Time with fraction"],
    ["10:30:00Z", "UTC time"],
    ["10:30:00+09:00", "Time with timezone"],

    # Date-times
    ["2024-01-15T10:30:00Z", "DateTime UTC"],
    ["2024-01-15T10:30:00+09:00", "DateTime with timezone"],

    # Durations
    ["P1Y2M3DT4H5M6S", "Full duration"],
    ["PT30M", "30 minutes duration"],
    ["P1D", "1 day duration"],
  ]

  examples.each do |input, description|
    puts "#{description}:"
    puts "  Input:  #{input}"
    result = parse_iso8601(input)
    if result
      puts "  Result: #{result.inspect}"
      puts "  String: #{result}"
      if result.respond_to?(:to_date)
        puts "  Date:   #{begin
          result.to_date
        rescue StandardError
          'N/A'
        end}"
      end
      puts "  Seconds: #{result.to_seconds}" if result.respond_to?(:to_seconds)
    end
    puts
  end
end
