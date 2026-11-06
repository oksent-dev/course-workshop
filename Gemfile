source "https://rubygems.org"

ruby file: ".ruby-version"

gem "rails", "~> 8.1.4", ">= 8.1.4.1"
gem "propshaft"
gem "pg", "~> 1.7"
gem "puma", ">= 6.0"
gem "jsbundling-rails"
gem "tailwindcss-rails", "~> 4.7"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "rails-i18n", "~> 8.1"
gem "commonmarker", "~> 2.10"
gem "rouge", "~> 5.1"
gem "mcp", "~> 1.9", require: false
gem "image_processing", "~> 1.2", require: false

gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "dotenv-rails", "~> 3.2"
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
