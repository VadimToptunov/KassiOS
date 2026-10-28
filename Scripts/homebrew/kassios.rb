# Homebrew formula for the KassiOS host-side tools. The release workflow fills in
# the version and checksum; copy the result to the tap
# (github.com/VadimToptunov/homebrew-tap, Formula/kassios.rb).
class Kassios < Formula
  desc "Host-side tools for KassiOS: kassios-agent, kassios-mutants, kassios-lint"
  homepage "https://github.com/VadimToptunov/KassiOS"
  url "https://github.com/VadimToptunov/KassiOS/releases/download/@VERSION@/kassios-@VERSION@-macos.zip"
  sha256 "@SHA256@"
  license "MIT"

  depends_on :macos

  def install
    bin.install Dir["bin/*"]
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/kassios version").strip
  end
end
