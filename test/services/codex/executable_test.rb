require "test_helper"
require "tmpdir"

class CodexExecutableTest < ActiveSupport::TestCase
  test "explicit commands and paths are kept without desktop discovery" do
    [ "codex", "C:/Tools/Codex/codex.exe", "/usr/local/bin/codex" ].each do |configured|
      assert_equal configured, Codex::Executable.resolve(configured, windows: false, local_app_data: nil)
    end
  end

  test "desktop resolution finds the newest runtime and checks again after an update" do
    Dir.mktmpdir do |directory|
      old = install_runtime(directory, "a1", Time.at(10))
      assert_equal old, resolve_desktop(directory)
      current = install_runtime(directory, "b2", Time.at(20))
      install_runtime(directory, "unrelated", Time.at(30))
      assert_equal current, resolve_desktop(directory)
      assert_equal current, resolve_desktop(directory.tr("/", "\\")) if Gem.win_platform?
      File.rename(current, "#{current}.old")
      replacement = install_runtime(directory, "c3", Time.at(40))
      assert_equal replacement, resolve_desktop(directory)
    end
  end

  test "a missing or unsupported desktop installation has a distinct error" do
    Dir.mktmpdir do |directory|
      [ { windows: true, local_app_data: directory }, { windows: false, local_app_data: directory },
        { windows: true, local_app_data: nil } ].each do |options|
        error = assert_raises(LocalAi::Error) { Codex::Executable.resolve("codex-desktop", **options) }
        assert_equal "runtime_not_found", error.code
      end
    end
  end

  private

  def resolve_desktop(directory)
    Codex::Executable.resolve("codex-desktop", windows: true, local_app_data: directory)
  end

  def install_runtime(directory, version, timestamp)
    path = File.join(directory, "OpenAI", "Codex", "bin", version, "codex.exe")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "test executable")
    File.utime(timestamp, timestamp, path)
    path
  end
end
