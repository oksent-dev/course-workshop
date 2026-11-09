require "bundler/setup"
require "selenium-webdriver"
require "fileutils"

root = File.expand_path("..", __dir__)
destination = File.join(root, "docs/screenshots")
FileUtils.mkdir_p(destination)
base_url = ENV.fetch("DEMO_URL", "http://localhost:3001").delete_suffix("/")
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument("--headless=new")
driver = Selenium::WebDriver.for(:chrome, options: options)
wait = Selenium::WebDriver::Wait.new(timeout: 20, ignore: [ Selenium::WebDriver::Error::StaleElementReferenceError ])

begin
  driver.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1440, height: 1100, deviceScaleFactor: 1, mobile: false)
  driver.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
  driver.navigate.to("#{base_url}/en")
  raise "Screenshot capture requires the public demo" if driver.find_elements(css: "[data-demo-notice]").empty?
  driver.execute_async_script("const done = arguments[arguments.length - 1]; document.fonts.ready.then(done)")
  wait.until { driver.execute_script("return Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)") }
  driver.save_screenshot(File.join(destination, "library.png"))

  driver.find_element(css: "a[aria-label='Statistics over coffee']").click
  wait.until { driver.find_element(css: "h1").text == "Statistics over coffee" }
  lesson_urls = driver.find_elements(css: "main a[href*='/lessons/']").map { |link| link.attribute("href") }.uniq
  raise "Expected four demo lessons" unless lesson_urls.size == 4
  driver.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1440, height: 1400, deviceScaleFactor: 1, mobile: false)
  driver.navigate.to(lesson_urls[1])
  wait.until { driver.find_elements(css: ".lesson-block-output .katex").any? }
  driver.execute_async_script("const done = arguments[arguments.length - 1]; document.fonts.ready.then(done)")
  driver.save_screenshot(File.join(destination, "reader.png"))

  driver.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1440, height: 1100, deviceScaleFactor: 1, mobile: false)
  driver.execute_script("document.querySelector('.lesson-content table').closest('.lesson-scroll').scrollIntoView({block: 'start'})")
  driver.save_screenshot(File.join(destination, "code.png"))

  driver.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1440, height: 1400, deviceScaleFactor: 1, mobile: false)
  driver.navigate.to(lesson_urls[3])
  wait.until { driver.find_elements(css: ".lesson-block-output svg").any? }
  driver.save_screenshot(File.join(destination, "diagram.png"))
  puts "Saved library, reader, code and diagram screenshots in docs/screenshots."
ensure
  driver.quit
end
