require "vips"

module DemoIllustrations
  def self.generate!
    Vips.block("VipsForeignLoadSvgBuffer", false)
    save(Rails.root.join("db/demo/cover.svg").read, "cw-demo-cover-v1.png")
    { pl: [ "Pięć wizyt w kawiarni", "Mediana: 8 min", "Średnia: 12 min", "Czas oczekiwania (minuty)", "Wizyta" ],
      en: [ "Five café visits", "Median: 8 min", "Mean: 12 min", "Waiting time (minutes)", "Visit" ] }.each do |language, labels|
      save(chart(labels), "cw-demo-chart-#{language}-v1.png")
    end
  ensure
    Vips.block("VipsForeignLoadSvgBuffer", true)
  end

  def self.save(svg, filename)
    Vips::Image.svgload_buffer(svg).pngsave(Rails.root.join("public/demo-media", filename).to_s, strip: true)
  end

  def self.chart(labels)
    title, median, mean, axis, visit = labels
    grid = (0..40).step(10).map do |value|
      x = 120 + value * 18
      %(<path d="M#{x}150v320" stroke="#d6d8c8"/><text x="#{x}" y="500" text-anchor="middle">#{value}</text>)
    end.join
    bars = [ 4, 6, 8, 10, 32 ].each_with_index.map do |value, index|
      y = 175 + index * 58
      %(<text x="98" y="#{y + 7}" text-anchor="end">#{('A'.ord + index).chr}</text><rect x="120" y="#{y - 16}" width="#{value * 18}" height="32" rx="5" fill="#63805d"/><text x="#{132 + value * 18}" y="#{y + 7}">#{value}</text>)
    end.join
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="960" height="560" viewBox="0 0 960 560">
        <rect width="960" height="560" rx="24" fill="#fbf8ef"/>
        <g font-family="Arial, DejaVu Sans, sans-serif" font-size="20" fill="#303b32">
          <text x="60" y="60" font-size="30" font-weight="bold">#{title}</text>
          <path d="M60 105h35" stroke="#303b32" stroke-width="3" stroke-dasharray="8 5"/>
          <text x="108" y="112">#{median}</text>
          <path d="M400 105h35" stroke="#795639" stroke-width="3" stroke-dasharray="2 5"/>
          <text x="448" y="112">#{mean}</text>
          <text x="60" y="145" font-size="16">#{visit}</text>
          #{grid}#{bars}
          <path d="M264 150v320" stroke="#303b32" stroke-width="3" stroke-dasharray="8 5"/>
          <path d="M336 150v320" stroke="#795639" stroke-width="3" stroke-dasharray="2 5"/>
          <text x="480" y="540" text-anchor="middle">#{axis}</text>
        </g>
      </svg>
    SVG
  end
end
