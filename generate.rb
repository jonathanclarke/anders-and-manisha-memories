#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "fileutils"
require "rqrcode"
require "mini_magick"

MAP_FILE = "map.csv"
QR_OUTPUT_DIR = "qrs"
HTML_OUTPUT_DIR = "docs"

QR_SIZE_PIXELS = 670         # Base size of QR code image (approx)


FONT = "/usr/share/fonts/opentype/urw-base35/Z003-MediumItalic.otf"
FONT_SIZE = 72
BOTTOM_MARGIN = 30           # Space below QR for the text

# Set this to your GitHub Pages base URL
HTML_BASE_URL = "https://jonathanclarke.github.io/anders-and-manisha-memories"
USE_HTML_URL_FOR_QR = true   # If false, QR will point directly to video URL (col 2)

FileUtils.mkdir_p(QR_OUTPUT_DIR)
FileUtils.mkdir_p(HTML_OUTPUT_DIR)

unless File.exist?(MAP_FILE)
  warn "ERROR: #{MAP_FILE} not found in current directory."
  exit 1
end

CSV.foreach(MAP_FILE, col_sep: ";") do |row|
  index     = row[0]&.strip     # e.g. "001"
  video_url = row[1]&.strip     # e.g. direct mp4 link
  name      = row[2]&.strip     # e.g. "Axel Rydén"

  next if index.nil? || index.empty? || video_url.nil? || video_url.empty?

  # Where to save QR & HTML
  qr_output_path   = File.join(QR_OUTPUT_DIR, "#{index}.png")
  html_output_path = File.join(HTML_OUTPUT_DIR, "#{index}.html")

  # URL encoded in the QR
  qr_target_url =
    if USE_HTML_URL_FOR_QR
      "#{HTML_BASE_URL}/#{index}.html"
    else
      video_url
    end

  puts "Processing #{index}:"
  puts "  Video: #{video_url}"
  puts "  Name : #{name}"
  puts "  QR   : #{qr_output_path} -> #{qr_target_url}"
  puts "  HTML : #{html_output_path}"

  # 1. Generate QR code PNG (basic black/white)
  qrcode = RQRCode::QRCode.new(qr_target_url)

  png = qrcode.as_png(
    size: QR_SIZE_PIXELS,
    border_modules: 4,
    module_px_size: 6
  )

  # Save temporary QR image
  temp_qr_path = File.join(QR_OUTPUT_DIR, "tmp_#{index}.png")
  File.binwrite(temp_qr_path, png.to_s)

  # 2. Open QR image and add space + text at the bottom
  image = MiniMagick::Image.open(temp_qr_path)

  if name && !name.empty?
    image.combine_options do |c|
      # Add extra white space at the bottom
      c.gravity "south"
      c.background "white"
      c.splice "0x#{BOTTOM_MARGIN}"

      # Add the text in that space
      c.font FONT
      c.pointsize FONT_SIZE
      c.fill "black"
      c.annotate "+0+10", name
    end
  end

  image.write(qr_output_path)
  File.delete(temp_qr_path) if File.exist?(temp_qr_path)

  # 3. Generate HTML file in docs/<index>.html
  html_content = <<~HTML
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Message from #{name || "Friend"}</title>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body {
          margin: 0;
          padding: 0;
          background: #000;
          color: #fff;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        h1 {
          font-size: 1.2rem;
          margin: 0.5rem 0 1rem;
          text-align: center;
        }
        video {
          width: 100%;
          max-width: 800px;
          max-height: 100vh;
        }
      </style>
    </head>
    <body>
      #{name && !name.empty? ? "<h1>Message from #{name}</h1>" : ""}
      <video controls autoplay>
        <source src="#{video_url}" type="video/mp4">
        Your browser does not support the video tag.
      </video>
    </body>
    </html>
  HTML

  File.write(html_output_path, html_content)
end

puts "Done. QR codes saved in #{QR_OUTPUT_DIR}/ and HTML pages in #{HTML_OUTPUT_DIR}/"
