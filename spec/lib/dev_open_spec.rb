# frozen_string_literal: true

require "rails_helper"
require "socket"
require "stringio"
require "dev_open"

RSpec.describe DevOpen do
  let(:server) { TCPServer.new("127.0.0.1", 0) }
  let!(:port) { server.addr[1] }
  let(:opened) { [] }
  let(:opener) { ->(cmd, url) { opened << [ cmd, url ] } }
  let(:out) { StringIO.new }
  let(:quickstart) { "/docs/developer/quickstart" }

  after { server.close unless server.closed? }

  def open_page(env: {}, host_os: "darwin", port: self.port, wait: 1)
    described_class.call(port:, path: quickstart, env:, host_os:, opener:, wait:, tick: 0.05, out:)
  end

  it "opens the page once the server answers" do
    expect(open_page).to eq(:opened)
    expect(opened).to eq([ [ "open", "http://localhost:#{port}#{quickstart}" ] ])
  end

  it "uses xdg-open on a Linux desktop" do
    Dir.mktmpdir do |bin|
      FileUtils.touch(File.join(bin, "xdg-open"))
      File.chmod(0o755, File.join(bin, "xdg-open"))

      expect(open_page(env: { "PATH" => bin, "DISPLAY" => ":0" }, host_os: "linux-gnu")).to eq(:opened)
      expect(opened.first.first).to eq("xdg-open")
    end
  end

  it "prints the URL instead when there is no opener" do
    expect(open_page(env: { "PATH" => "/nonexistent", "DISPLAY" => ":0" }, host_os: "linux-gnu")).to eq(:printed)
    expect(opened).to be_empty
    expect(out.string).to include("Open: http://localhost:#{port}#{quickstart}")
  end

  it "never opens inside a container" do
    expect(open_page(env: { "CODESPACES" => "true", "CODESPACE_NAME" => "demo", "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev" })).to eq(:printed)
    expect(opened).to be_empty
  end

  it "gives up quietly when the server never answers" do
    server.close

    expect(open_page(wait: 0.2)).to eq(:timed_out)
    expect(opened).to be_empty
    expect(out.string).to include("http://localhost:#{port}#{quickstart}")
  end
end
