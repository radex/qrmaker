require 'rubygems'
require 'rqrcode'
require 'prawn'
require 'prawn/measurements'
require 'prawn/qrcode'
require 'prawn-svg'
require 'color'
require 'rmagick'
require 'json'
require 'zlib'
require 'date'

include Prawn::Measurements

# module Prawn
#   module Text
#     module Formatted #:nodoc:
#       # @private
#       class LineWrap #:nodoc:
#         def whitespace()
#           # Wrap by these special characters as well
#           "&:/\\" +
#           "\s\t#{zero_width_space()}"
#         end
#       end
#     end
#   end
# end

def render_identicode(data, id, extent)
  pts = [[0, 0], [0, 1], [1, 1], [1, 0], [0, 0]]

  4.times do |n|
    color = Color::HSL.from_fraction((id % 6) / 6.0, 1.0, 0.3).html[1..6]
    id /= 6

    save_graphics_state do
      soft_mask do
        fill_color 'ffffff'
        polygon = [pts[n], [0.5, 0.5], pts[n+1]].map{ |v| [v[0]*bounds.height, v[1]*bounds.height] }
        fill_polygon(*(polygon))
      end

      print_qr_code data, stroke: false,
                          extent: extent, foreground_color: color,
                          pos: [bounds.left, bounds.top]
    end
  end

  fill_color '000000'
end

DYMO_LABEL_SIZE = [89, 36]
ZEBRA_LABEL_SIZE = [100, 60]
A8_SAFE_SIZE = [47, 67]

def draw_page item
  stroke_bounds

  margin = mm2pt(2)

  bounding_box([bounds.left + margin, bounds.top - margin],
    height: bounds.height - 2*margin, width: bounds.width - 2*margin) do
    bounding_box(bounds.top_left, width: bounds.width, height: 28) do
      text_box item[:name],
        size: 15, align: :center, valign: :center, width: bounds.width,
        inline_format: true, overflow: :shrink_to_fit, disable_wrap_by_char: false
    end

    bounding_box([bounds.left, bounds.top - 30], width: bounds.width) do
      print_qr_code item[:url], stroke: false,
        foreground_color: '000000',
        extent: bounds.width, margin: 0, pos: bounds.top_left
    end

    bounding_box([bounds.left, bounds.bottom + 23], width: bounds.width, height: 25) do
      text_box item[:extra],
        size: 9, align: :center, valign: :center, width: bounds.width,
        inline_format: true, overflow: :shrink_to_fit, disable_wrap_by_char: false
    end
  end
end

def render_label(item, size: DYMO_LABEL_SIZE)
  pdf = Prawn::Document.new(page_size: size.map { |x| mm2pt(x) },
                            margin: [0, 0, 0, 0].map { |x| mm2pt(x) }) do
    font_families.update("DejaVuSans" => {
      normal: "fonts/DejaVuSans.ttf",
      italic: "fonts/DejaVuSans-Oblique.ttf",
      bold: "fonts/DejaVuSans-Bold.ttf",
      bold_italic: "fonts/DejaVuSans-BoldOblique.ttf"
    })
    font 'DejaVuSans'

    draw_page item
    start_new_page
    draw_page item
  end

  pdf.render
end

# get '/api/1/preview/:id.pdf' do
#   headers["Content-Type"] = "application/pdf; charset=utf8"
#   render_label params["id"]
# end

# get '/api/1/preview/:id.png' do
#   headers["Content-Type"] = "image/png"
#   img = Magick::ImageList.new()
#   img = img.from_blob(render_label(params["id"])){ self.density = 200 }.first
#   img.format = 'png'
#   img.background_color = 'white'
#   img.to_blob
# end

# post '/api/1/print/:id' do
#   temp = Tempfile.new('labelmaker')
#   temp.write(render_label(params["id"]))
#   temp.close
#   system("lpr -P DYMO_LabelWriter_450 #{temp.path}")
# end

label = {
  name: 'Hello world blah blah blah blah',
  url: 'https://example.com/',
  extra: 'Auchan hehe'
}

pdf = render_label(label, size: A8_SAFE_SIZE)
path = "#{Dir.home}/Downloads/QRs (#{DateTime.now().to_s}).pdf"
p path
File.write(path, pdf)
system("open '#{path}'")
