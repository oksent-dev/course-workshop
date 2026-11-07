require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]

  def switch_interface_language(name)
    find("[data-language-menu-target=trigger]").click
    click_link name, exact: true
  end
end
