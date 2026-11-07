namespace :brand do
  desc "Regenerate browser and touch icons from the canonical logo"
  task icons: :environment do
    require "vips"

    document = Nokogiri::XML(Rails.root.join("app/assets/images/logo.svg").read) { |config| config.strict.nonet }
    root = document.root
    root["fill"] = "#fbf8ef"
    background = Nokogiri::XML::Node.new("rect", document)
    background.namespace = root.namespace
    { "width" => "80", "height" => "80", "rx" => "16", "fill" => "#435f48" }.each { |key, value| background[key] = value }
    root.prepend_child(background)
    svg = document.to_xml
    Rails.root.join("public/icon.svg").write(svg)
    Vips.block("VipsForeignLoadSvgBuffer", false)
    Vips::Image.svgload_buffer(svg, scale: 32.0 / 80).pngsave(Rails.root.join("public/icon.png").to_s, strip: true)

    background["rx"] = "0"
    Vips::Image.svgload_buffer(document.to_xml, scale: 180.0 / 80).pngsave(Rails.root.join("public/apple-touch-icon.png").to_s, strip: true)
  ensure
    Vips.block("VipsForeignLoadSvgBuffer", true) if defined?(Vips)
  end
end
