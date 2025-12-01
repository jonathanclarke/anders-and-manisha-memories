#!/usr/bin/env ruby
# frozen_string_literal: true

# Layout many QR images onto A4 pages and export as a multi-page PDF.
#
# Usage:
#   ruby pages.rb qrs/ printable-output.pdf
#
# Requirements:
#   - ImageMagick installed (convert, composite binaries)
#   - gem install mini_magick

require "mini_magick"

# ------------- CLI ARGS -------------

INPUT_DIR  = ARGV[0] || "qrs"
OUTPUT_PDF = ARGV[1] || "qr_sheets.pdf"

unless Dir.exist?(INPUT_DIR)
  warn "Input directory #{INPUT_DIR.inspect} does not exist."
  exit 1
end

# ------------- PAGE + LAYOUT SETTINGS -------------

DPI = 300

# A4 size in inches: 8.27 x 11.69
PAGE_WIDTH  = (8.27 * DPI).round  # ~2481 px
PAGE_HEIGHT = (11.69 * DPI).round # ~3507 px

# Your QR codes are ~200 x 230 px
QR_WIDTH  = 200
QR_HEIGHT = 230

# Margins around the page (space at edges)
MARGIN_X = 100  # left/right
MARGIN_Y = 100  # top/bottom

# Padding between QR codes
GUTTER_X = 40   # horizontal
GUTTER_Y = 40   # vertical

# Derived layout values
CELL_WIDTH  = QR_WIDTH  + GUTTER_X
CELL_HEIGHT = QR_HEIGHT + GUTTER_Y

usable_width  = PAGE_WIDTH  - (2 * MARGIN_X)
usable_height = PAGE_HEIGHT - (2 * MARGIN_Y)

COLS = [usable_width  / CELL_WIDTH, 1].max
ROWS = [usable_height / CELL_HEIGHT, 1].max
PER_PAGE = COLS * ROWS

puts "Page size: #{PAGE_WIDTH}x#{PAGE_HEIGHT} px (A4 @ #{DPI} DPI)"
puts "QR size:   #{QR_WIDTH}x#{QR_HEIGHT} px"
puts "Margins:   #{MARGIN_X}px left/right, #{MARGIN_Y}px top/bottom"
puts "Gutters:   #{GUTTER_X}px horizontal, #{GUTTER_Y}px vertical"
puts "Grid:      #{COLS} columns x #{ROWS} rows => #{PER_PAGE} per page"

# ------------- COLLECT INPUT FILES -------------

qr_files = Dir.glob(File.join(INPUT_DIR, "*.{png,jpg,jpeg}"), File::FNM_CASEFOLD).sort

if qr_files.empty?
  warn "No images found in #{INPUT_DIR.inspect}"
  exit 1
end

puts "Found #{qr_files.size} QR images."

# ------------- HELPERS -------------

def new_blank_page(path)
  MiniMagick::Tool::Convert.new("convert") do |convert|
    convert.size "#{PAGE_WIDTH}x#{PAGE_HEIGHT}"
    convert.xc "white"                 # white background
    convert.units "PixelsPerInch"
    convert.density DPI.to_s
    convert << path
  end
end

# ------------- LAYOUT LOOP -------------

page_paths = []
page_index = 0
item_index = 0
current_page_path = nil

qr_files.each_with_index do |qr_path, idx|
  # Start a new page if needed
  if item_index % PER_PAGE == 0
    page_index += 1
    current_page_path = "page_#{"%03d" % page_index}.png"
    puts "Creating #{current_page_path}..."
    new_blank_page(current_page_path)
    page_paths << current_page_path
  end

  # Compute row/col position on this page
  local_index = item_index % PER_PAGE
  row = local_index / COLS
  col = local_index % COLS

  x = MARGIN_X + col * CELL_WIDTH + (GUTTER_X / 2)
  y = MARGIN_Y + row * CELL_HEIGHT + (GUTTER_Y / 2)

  puts "Placing #{File.basename(qr_path)} on #{current_page_path} at (#{x}, #{y})"

  MiniMagick::Tool::Composite.new("composite") do |composite|
    composite.geometry "+#{x}+#{y}"
    composite << qr_path
    composite << current_page_path
    composite << current_page_path # overwrite original page with composite
  end

  item_index += 1
end

# ------------- COMBINE TO MULTI-PAGE PDF -------------

puts "Combining #{page_paths.size} pages into #{OUTPUT_PDF}..."

MiniMagick::Tool::Convert.new("convert") do |convert|
  page_paths.each { |p| convert << p }
  convert << OUTPUT_PDF
end

puts "Done. Output file: #{OUTPUT_PDF}"
