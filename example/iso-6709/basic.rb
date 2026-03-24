# frozen_string_literal: true

# ISO 6709 Geographic Coordinate Parser - Ruby Implementation
#
# Parse ISO 6709 geographic point locations (latitude, longitude, altitude).
#
# Run with: ruby example/iso-6709/basic.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "parsanol/parslet"

# ISO 6709 coordinate parser
class Iso6709Parser < Parsanol::Parser
  root :coordinate

  # Sign: + for N/E, - for S/W
  rule(:lat_sign) { (str("+") | str("-")).as(:lat_sign) }
  rule(:lon_sign) { (str("+") | str("-")).as(:lon_sign) }

  # Decimal degrees: DD.DDDD or DDD.DDDD
  rule(:decimal_deg) do
    match("[0-9]").repeat(1, 2).as(:degrees) >>
      (str(".") >> match("[0-9]").repeat(1)).maybe.as(:fraction)
  end

  rule(:decimal_deg_3) do
    match("[0-9]").repeat(1, 3).as(:degrees) >>
      (str(".") >> match("[0-9]").repeat(1)).maybe.as(:fraction)
  end

  # Sexagesimal (DMS): DD MM SS.ss or DD MM
  rule(:sexagesimal) do
    match("[0-9]").repeat(1, 2).as(:degrees) >>
      (
        space >>
        match("[0-9]").repeat(1, 2).as(:minutes) >>
        (
          space >>
          match("[0-9]").repeat(1, 2).as(:seconds) >>
          (str(".") >> match("[0-9]").repeat(1)).maybe.as(:sec_fraction)
        ).maybe
      ).maybe
  end

  rule(:sexagesimal_3) do
    match("[0-9]").repeat(1, 3).as(:degrees) >>
      (
        space >>
        match("[0-9]").repeat(1, 2).as(:minutes) >>
        (
          space >>
          match("[0-9]").repeat(1, 2).as(:seconds) >>
          (str(".") >> match("[0-9]").repeat(1)).maybe.as(:sec_fraction)
        ).maybe
      ).maybe
  end

  # Latitude: -90 to +90
  rule(:latitude) do
    lat_sign >> (decimal_deg | sexagesimal).as(:latitude)
  end

  # Longitude: -180 to +180
  rule(:longitude) do
    lon_sign >> (decimal_deg_3 | sexagesimal_3).as(:longitude)
  end

  # Altitude (optional): +AAA.A or -AAA.A
  rule(:altitude) do
    (str("+") | str("-")).as(:alt_sign) >>
      match("[0-9]").repeat(1).as(:alt_value) >>
      (str(".") >> match("[0-9]").repeat(1)).maybe.as(:alt_fraction)
  end

  # Coordinate Reference System (optional): CRScode/
  rule(:crs) do
    str("CRS") >>
      match("[A-Z0-9_]").repeat(1).as(:crs) >>
      str("/")
  end

  # Complete coordinate
  rule(:coordinate) do
    latitude >>
      (space | str("")).maybe >>
      longitude >>
      altitude.maybe.as(:altitude) >>
      (str("/") >> crs).maybe.as(:crs_info)
  end

  rule(:space) { match('\s') }
end

# Coordinate result class
Coordinate = Struct.new(:lat_sign, :latitude, :lon_sign, :longitude, :altitude,
                        :crs) do
  def to_h
    {
      latitude: lat_value,
      longitude: lon_value,
      altitude: alt_value,
      crs: crs,
    }.compact
  end

  def lat_value
    return nil unless latitude

    val = degrees_to_decimal(latitude)
    lat_sign == "-" ? -val : val
  end

  def lon_value
    return nil unless longitude

    val = degrees_to_decimal(longitude)
    lon_sign == "-" ? -val : val
  end

  def alt_value
    return nil unless altitude

    val = altitude[:alt_value].to_f
    val += altitude[:alt_fraction].to_s.to_f if altitude[:alt_fraction]
    altitude[:alt_sign] == "-" ? -val : val
  end

  private

  def degrees_to_decimal(d)
    return 0.0 unless d

    deg = d[:degrees].to_i
    min = d[:minutes].to_s.to_i
    sec = d[:seconds].to_s.to_f
    sec += d[:sec_fraction].to_s.to_f if d[:sec_fraction]
    frac = d[:fraction].to_s.to_f

    deg + (min / 60.0) + (sec / 3600.0) + frac
  end
end

# Transform parse tree to Coordinate
class Iso6709Transform < Parsanol::Transform
  rule(
    lat_sign: simple(:ls),
    latitude: simple(:lat),
    lon_sign: simple(:lons),
    longitude: simple(:lon),
  ) do
    Coordinate.new(ls.to_s, lat, lons.to_s, lon, nil, nil)
  end

  rule(
    lat_sign: simple(:ls),
    latitude: simple(:lat),
    lon_sign: simple(:lons),
    longitude: simple(:lon),
    altitude: simple(:alt),
  ) do
    Coordinate.new(ls.to_s, lat, lons.to_s, lon, alt, nil)
  end

  rule(
    lat_sign: simple(:ls),
    latitude: simple(:lat),
    lon_sign: simple(:lons),
    longitude: simple(:lon),
    crs_info: simple(:crs),
  ) do
    Coordinate.new(ls.to_s, lat, lons.to_s, lon, nil, crs.to_s)
  end

  rule(
    lat_sign: simple(:ls),
    latitude: simple(:lat),
    lon_sign: simple(:lons),
    longitude: simple(:lon),
    altitude: simple(:alt),
    crs_info: simple(:crs),
  ) do
    Coordinate.new(ls.to_s, lat, lons.to_s, lon, alt, crs.to_s)
  end
end

# Parse and return Coordinate
def parse_coordinate(str)
  parser = Iso6709Parser.new
  transform = Iso6709Transform.new

  tree = parser.parse(str)
  transform.apply(tree)
rescue Parsanol::ParseError => e
  puts "Parse error: #{e.message}"
  nil
end

# Main demo
if __FILE__ == $PROGRAM_NAME
  puts "ISO 6709 Geographic Coordinate Parser"
  puts "=" * 50
  puts

  coordinates = [
    "+40.6894-074.0447",                    # Statue of Liberty
    "+48.8584+002.2945",                    # Eiffel Tower
    "-90+000",                              # South Pole
    "+27.9881+086.9250",                    # Mount Everest
    "+40 41 21.84-074 02 40.92", # Sexagesimal format
    "+48.8584+002.2945+330CRSWGS_84/", # With altitude and CRS
  ]

  coordinates.each do |coord_str|
    puts "Input: #{coord_str}"
    result = parse_coordinate(coord_str)
    if result
      puts "  Latitude:  #{result.lat_value}"
      puts "  Longitude: #{result.lon_value}"
      puts "  Altitude:  #{result.alt_value}" if result.alt_value
      puts "  CRS:       #{result.crs}" if result.crs
    end
    puts
  end

  # Validation examples
  puts "-" * 50
  puts "Validation examples:"
  puts

  ["+95-074", "+40.6894"].each do |invalid|
    puts "Invalid: #{invalid}"
    result = parse_coordinate(invalid)
    puts "  Result: #{result.inspect}"
    puts
  end
end
