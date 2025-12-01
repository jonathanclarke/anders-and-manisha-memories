#!/usr/bin/env ruby
# frozen_string_literal: true

# Layout many QR images onto A4 pages (4 per row, 2 rows = 8 per page)
# and export as a multi-page PDF.
#
# Usage:
#   ruby pages.rb qrs/ output.pdf
#
# Requirements:
#   - ImageMagick installed (convert, composite, identify)
#   - Ruby standard library only (no gems)

require "shellwords"
require "fileutils"

INPUT_DIR  = ARGV[0] || "qrs"
OUTPUT_PDF = ARGV[1] || "qr_sheets.pdf"

unless Dir.exist?(INPUT_DIR)
  warn "Input directory #{INPUT_DIR.inspect} does not exist."
  exit 1
end

# -------- PAGE SETTINGS --------

DPI = 300

# A4 at 300 DPI
PAGE_WIDTH  = (8.27 * DPI).round  # ~2481 px
PAGE_HEIGHT = (11.69 * DPI).round # ~3507 px

# Grid: 4 columns × 2 rows = 8 per page
COLS = 2
ROWS = 3
PER_PAGE = COLS * ROWS

# Target width for each QR card (QR + name), height is auto from aspect ratio
TARGET_QR_WIDTH = 670  # px; tweak if you want larger/smaller

# Gaps between items
GUTTER_X = 400   # horizontal gap between cards
GUTTER_Y = 200  # vertical gap between cards

# Directory to hold resized copies
TMP_DIR = "resized_qrs"
FileUtils.mkdir_p(TMP_DIR)

# -------- HELPERS --------

def run!(cmd)
  puts "CMD: #{cmd}"
  success = system(cmd)
  raise "Command failed: #{cmd}" unless success
end

def resize_image(src, dst, target_width)
  s = Shellwords.escape(src)
  d = Shellwords.escape(dst)
  # Resize to target width, preserve aspect ratio
  run!(%Q[convert #{s} -resize #{target_width}x #{d}])
end

def identify_size(path)
  p = Shellwords.escape(path)
  out = `identify -format "%w %h" #{p}`.strip
  raise "identify failed for #{path}" if out.empty?
  w, h = out.split.map(&:to_i)
  [w, h]
end

def new_blank_page(path)
  escaped = Shellwords.escape(path)
  run!(%Q[convert -size #{PAGE_WIDTH}x#{PAGE_HEIGHT} xc:white -units PixelsPerInch -density #{DPI} #{escaped}])
end

def composite_image(qr_path, page_path, x, y)
  qr   = Shellwords.escape(qr_path)
  page = Shellwords.escape(page_path)
  run!(%Q[composite -geometry +#{x}+#{y} #{qr} #{page} #{page}])
end

# -------- COLLECT + RESIZE INPUT FILES --------

src_files = Dir.glob(File.join(INPUT_DIR, "*.{png,jpg,jpeg}"), File::FNM_CASEFOLD).sort

if src_files.empty?
  warn "No images found in #{INPUT_DIR.inspect}"
  exit 1
end

puts "Found #{src_files.size} QR images."

# Resize all source images into TMP_DIR
resized_files = []

src_files.each do |src|
  dst = File.join(TMP_DIR, File.basename(src))
  resize_image(src, dst, TARGET_QR_WIDTH)
  resized_files << dst
end

# Use the first resized image to get final card dimensions
QR_WIDTH, QR_HEIGHT = identify_size(resized_files.first)

puts "Page size: #{PAGE_WIDTH}x#{PAGE_HEIGHT} px (A4 @ #{DPI} DPI)"
puts "Grid:      #{COLS} columns x #{ROWS} rows => #{PER_PAGE} per page"
puts "Card size: #{QR_WIDTH}x#{QR_HEIGHT} px (after resize)"
puts "Gutters:   #{GUTTER_X}px horizontal, #{GUTTER_Y}px vertical"

# Compute centered margins based on card + gutter sizes
total_grid_width  = COLS * QR_WIDTH  + (COLS - 1) * GUTTER_X
total_grid_height = ROWS * QR_HEIGHT + (ROWS - 1) * GUTTER_Y

margin_left = (PAGE_WIDTH  - total_grid_width)  / 2
margin_top  = (PAGE_HEIGHT - total_grid_height) / 2

if margin_left < 0 || margin_top < 0
  raise "Layout does not fit on A4: reduce TARGET_QR_WIDTH or gutters."
end

puts "Computed margins: left=#{margin_left.round}px, top=#{margin_top.round}px"

# -------- LAYOUT LOOP --------

page_paths = []
page_index = 0
item_index = 0
current_page_path = nil

resized_files.each do |qr_path|
  # Start a new page if needed
  if item_index % PER_PAGE == 0
    page_index += 1
    current_page_path = "page_%03d.png" % page_index
    puts "Creating #{current_page_path}..."
    new_blank_page(current_page_path)
    page_paths << current_page_path
  end

  local_index = item_index % PER_PAGE
  row = local_index / COLS
  col = local_index % COLS

  x = margin_left + col * (QR_WIDTH + GUTTER_X)
  y = margin_top  + row * (QR_HEIGHT + GUTTER_Y)

  puts "Placing #{File.basename(qr_path)} on #{current_page_path} at (#{x.round}, #{y.round})"
  composite_image(qr_path, current_page_path, x.round, y.round)

  item_index += 1
end

# -------- COMBINE TO MULTI-PAGE PDF --------

puts "Combining #{page_paths.size} pages into #{OUTPUT_PDF}..."
escaped_pages = page_paths.map { |p| Shellwords.escape(p) }.join(" ")
escaped_out   = Shellwords.escape(OUTPUT_PDF)
run!(%Q[convert #{escaped_pages} #{escaped_out}])

puts "Done. Output file: #{OUTPUT_PDF}"
