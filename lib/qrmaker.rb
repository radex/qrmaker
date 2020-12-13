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
ZEBRA_4x6_SIZE = [100, 152]
A8_SAFE_SIZE = [44, 65]

def draw_page label
  return unless label
  line_width(0.2)
  stroke_bounds

  margin = mm2pt(1.5)

  bounding_box([bounds.left + margin, bounds.top - margin],
    height: bounds.height - 2*margin, width: bounds.width - 2*margin) do
    bounding_box(bounds.top_left, width: bounds.width, height: 28) do
      text_box label[:name],
        size: 15, align: :center, valign: :center, width: bounds.width,
        inline_format: true, overflow: :shrink_to_fit, disable_wrap_by_char: false
    end

    bounding_box([bounds.left, bounds.top - 30], width: bounds.width) do
      print_qr_code label[:url], stroke: false,
        foreground_color: '000000',
        extent: bounds.width, margin: 0, pos: bounds.top_left
    end

    bounding_box([bounds.left, bounds.bottom + 23], width: bounds.width, height: 25) do
      text_box label[:extra],
        size: 9, align: :center, valign: :center, width: bounds.width,
        inline_format: true, overflow: :shrink_to_fit, disable_wrap_by_char: false
    end
  end
end

def lay_out_4_labels_per_page labels
  page_size = ZEBRA_4x6_SIZE.map { |x| mm2pt(x) }
  label_size = A8_SAFE_SIZE.map { |x| mm2pt(x) }
  label_w = label_size[0]
  label_h = label_size[1]
  hmargin = (page_size[0] - 2*label_w) / 2
  vmargin = (page_size[1] - 2*label_h) / 2

  labels.each_slice(4).with_index do |label_slice, i|
    start_new_page unless i == 0

    bounding_box([bounds.left + hmargin, bounds.top - vmargin], width: label_w, height: label_h) do
      draw_page label_slice[0]
    end

    bounding_box([bounds.right - hmargin - label_w, bounds.top - vmargin], width: label_w, height: label_h) do
      draw_page label_slice[1]
    end

    bounding_box([bounds.left + hmargin, bounds.top - label_h - vmargin], width: label_w, height: label_h) do
      draw_page label_slice[2]
    end

    bounding_box([bounds.right - hmargin - label_w, bounds.top - label_h - vmargin], width: label_w, height: label_h) do
      draw_page label_slice[3]
    end
  end
end

def create_pdf(labels, size:)
  pdf = Prawn::Document.new(page_size: size.map { |x| mm2pt(x) },
                            margin: [0, 0, 0, 0].map { |x| mm2pt(x) }) do
    font_families.update("DejaVuSans" => {
      normal: "fonts/DejaVuSans.ttf",
      italic: "fonts/DejaVuSans-Oblique.ttf",
      bold: "fonts/DejaVuSans-Bold.ttf",
      bold_italic: "fonts/DejaVuSans-BoldOblique.ttf"
    })
    font 'DejaVuSans'

    # NOTE: This bit is appropriate for label printers that print 1/page
    # labels.each_with_index do |label, i|
    #   start_new_page unless i == 0
    #   draw_page label
    # end

    lay_out_4_labels_per_page labels
  end

  pdf.render
end

# get '/api/1/preview/:id.pdf' do
#   headers["Content-Type"] = "application/pdf; charset=utf8"
#   create_pdf params["id"]
# end

# get '/api/1/preview/:id.png' do
#   headers["Content-Type"] = "image/png"
#   img = Magick::ImageList.new()
#   img = img.from_blob(create_pdf(params["id"])){ self.density = 200 }.first
#   img.format = 'png'
#   img.background_color = 'white'
#   img.to_blob
# end

# post '/api/1/print/:id' do
#   temp = Tempfile.new('labelmaker')
#   temp.write(create_pdf(params["id"]))
#   temp.close
#   system("lpr -P DYMO_LabelWriter_450 #{temp.path}")
# end

labels = [
  {
    name: 'Hello world blah blah blah blah',
    url: 'https://example.com/',
    extra: 'Auchan hehe'
  },
  {
    name: 'asd;as daskd asldjkakld',
    url: 'https://example.org/',
    extra: 'Auchan hehe'
  },
  {
    name: 'Hi',
    url: 'https://example.biz/',
    extra: 'Auchan hehe'
  },
]

pdf = create_pdf(labels, size: ZEBRA_4x6_SIZE)
path = "#{Dir.home}/Downloads/QRs (#{DateTime.now().to_s}).pdf"
p path
File.write(path, pdf)
system("open '#{path}'")
