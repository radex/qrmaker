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
require 'nokogiri'
require 'rest-client'
require 'highline'

HighLine.colorize_strings

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

def lay_out_4_labels_per_page(labels, label_size:, page_size:)
  page_size = page_size.map { |x| mm2pt(x) }
  label_size = label_size.map { |x| mm2pt(x) }
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

def create_pdf(labels, label_size:, page_size:, four_per_page:)
  pdf = Prawn::Document.new(page_size: page_size.map { |x| mm2pt(x) },
                            margin: [0, 0, 0, 0].map { |x| mm2pt(x) }) do
    font_families.update("DejaVuSans" => {
      normal: "fonts/DejaVuSans.ttf",
      italic: "fonts/DejaVuSans-Oblique.ttf",
      bold: "fonts/DejaVuSans-Bold.ttf",
      bold_italic: "fonts/DejaVuSans-BoldOblique.ttf"
    })
    font 'DejaVuSans'

    if four_per_page
      lay_out_4_labels_per_page labels, label_size: label_size, page_size: page_size
    else
      labels.each_with_index do |label, i|
        start_new_page unless i == 0
        draw_page label
      end
    end
  end

  pdf.render
end

# get '/api/1/preview/:id.png' do
#   headers["Content-Type"] = "image/png"
#   img = Magick::ImageList.new()
#   img = img.from_blob(create_pdf(params["id"])){ self.density = 200 }.first
#   img.format = 'png'
#   img.background_color = 'white'
#   img.to_blob
# end

def generate_pdf(labels, print)
  puts JSON.dump(labels)
  pdf = create_pdf labels, label_size: A8_SAFE_SIZE, page_size: ZEBRA_4x6_SIZE, four_per_page: true

  tmp_dir = File.expand_path('../../tmp', __FILE__)
  # p tmp_dir
  Dir.mkdir(tmp_dir) rescue
  path = "#{tmp_dir}/QRs (#{DateTime.now().to_s}).pdf"
  p path

  File.write(path, pdf)

  if print
    begin
      system("lpr -P Zebra_4x6in_label_printer -o media=Custom.100x150mm '#{path}'")
    rescue
      system("open '#{path}'")
    end
  else
    system("open '#{path}'")
  end
rescue
  p "Something went wrong here..."
end

def get_auchan_details url
  raw = RestClient.get(url)
  html = Nokogiri::HTML.parse(raw)

  label = html.css(".product-resume .label")[0].text rescue "?"
  brand = html.css(".product-resume .brand")[0].text rescue "?"
  weight_and_price_per_weight = html.css(".product-resume .packaging")[0].text.strip.gsub(/\s{3,}/, ' |') rescue "?"
  price = html.css(".product-resume .price--promo, .product-resume .price--standard")[0]
    .text.strip.gsub(/\s{3,}/, ' ').sub(/(\d+) (\d+) /, '\1,\2') rescue "?"
  date = DateTime.now.strftime('%Y-%m-%d')

  extra = "#{brand} | #{price} | #{weight_and_price_per_weight} | #{date}"

  # require 'pry'; binding.pry

  return {
    name: label,
    url: url,
    extra: extra,
  }
end

def get_details url
  return get_auchan_details url if url.include? 'auchandirect.pl'
  return { name: '', url: url, extra: url }
rescue => error
  p error
  return { name: '?', url: url, extra: url }
end

def label_text label
  " Name:\t#{label[:name]}\n Extra:\t#{label[:extra]}\n URL:\t#{label[:url]}"
end

def from_json label
  { name: label["name"], url: label["url"], extra: label["extra"] }
end

def cli_create_label cli
  answer = cli.ask ("m - manual: \n" +
    "au - Auchan Direct search \n" +
    "al - Allegro search").yellow

  case answer
  when 'm'
    name = cli.ask "Name: "
    url = cli.ask "URL: "
    extra = cli.ask "Extra: "
    return { name: name, url: url, extra: extra }
  when 'au'
    query = cli.ask "Search query: "
    url = "https://www.auchandirect.pl/auchan-warszawa/pl/search?text=#{URI.escape(query)}"
    extra = "(Auchan Direct)"
    return { name: query, url: url, extra: extra }
  when 'al'
    query = cli.ask "Search query: "
    url = "https://allegro.pl/listing?string=#{URI.escape(query)}&order=d&allegro-smart-standard=1"
    extra = "(Allegro)"
    return { name: query, url: url, extra: extra }
  end

  return nil
end

def cli
  cli = HighLine.new

  labels = []

  loop do
    answer = cli.ask ("Enter product URL or: \n" +
      "c - create url (wizard)\n" +
      "p - print \n" +
      "g - generate PDF \n" +
      "j - dump json \n"+
      "l - load json \n"+
      "a - show all items \n" +
      "x - add last item again" +
      "d - delete last item").green
    label = nil

    case answer
    when /^https?:/
      label = get_details answer
    when 'c'
      label = cli_create_label cli
      cli.say "Sorry, not sure what you meant there...".red unless label
    when 'p'
      generate_pdf labels, true
    when 'g'
      generate_pdf labels, false
    when 'j'
      cli.say JSON.dump(labels)
    when 'l'
      json = cli.ask("Labels json:")
      begin
        labels.push(*JSON.parse(json).map { |l| from_json(l) })
      rescue
        cli.say "Oops, JSON load went wrong...".red
      end
    when 'd'
      labels.pop
    when 'x'
      if labels.last
        dups = cli.ask("How many '#{labels.last[:name]}' more to add? (press return = 1 more)", Integer) { |q| q.default = 1 }
        dups.times { labels << labels.last }
        cli.say "OK, added #{dups} more."
      end
    when 'a'
      cli.say labels.map { |l| label_text l }.join("\n\n")
    else
      cli.say "Sorry, not sure what you meant there...".red
    end

    if label
      labels << label
      cli.say "Added:\n#{label_text label}"
    end
    cli.say "\n"
  rescue => error
    p error
    cli.say "Oops, something went wrong here...".red
  end
end

cli
