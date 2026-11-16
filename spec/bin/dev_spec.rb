# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "socket"
require "dev_port"

RSpec.describe "bin/dev" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      stubs = @dir.join("stubs")
      stubs.mkpath
      { "gem" => "exit 0", "foreman" => 'echo "DEV_SERVER_PORT=$DEV_SERVER_PORT"; echo "$@"' }.each do |name, body|
        stubs.join(name).write("#!/bin/sh\n#{body}\n")
        stubs.join(name).chmod(0o755)
      end
      example.run
    end
  end

  def capture_dev(*args, env: {})
    path = "#{@dir.join('stubs')}:#{ENV.fetch('PATH')}"
    Open3.capture2e({ "PATH" => path, "PORT" => nil, "DEV_SERVER_PORT" => nil, "CODESPACES" => nil }.merge(env),
                    Rails.root.join("bin/dev").to_s, *args, chdir: @dir.to_s)
  end

  def run_dev(*args, env: {})
    output, status = capture_dev(*args, env:)
    expect(status).to be_success, output
    lines = output.lines.map(&:strip)
    exported = lines.index { |line| line.start_with?("DEV_SERVER_PORT=") }
    [ lines[exported].delete_prefix("DEV_SERVER_PORT="), lines[exported + 1] ]
  end

  it "exports the web port as DEV_SERVER_PORT and starts foreman on it" do
    port = DevPort.choose(3000, explicit: false, container: false)

    expect(run_dev).to eq([ port.to_s, "start -f Procfile.dev --port #{port}" ])
  end

  it "refuses a busy port given with -p, without a stack trace" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]

    output, status = capture_dev("-p", port.to_s)

    expect(status).not_to be_success
    expect(output.lines.size).to eq(1)
    expect(output).to include(port.to_s)
    expect(output).not_to include("EADDRINUSE")
  ensure
    server&.close
  end

  it "prints the app and quickstart URLs before starting foreman" do
    port = DevPort.choose(3000, explicit: false, container: false)

    output, = capture_dev("-p", port.to_s)

    expect(output).to include("http://localhost:#{port}/docs/developer/quickstart")
    expect(output.index("/docs/developer/quickstart")).to be < output.index("DEV_SERVER_PORT=")
  end

  it "takes the port from PORT" do
    expect(run_dev(env: { "PORT" => "3001" }).first).to eq("3001")
  end

  it "takes the port from .env over the shell, as foreman does" do
    @dir.join(".env").write("SIGNUP_MODE=open\nPORT=\"3002\"\n")

    expect(run_dev(env: { "PORT" => "3001" }).first).to eq("3002")
  end

  it "takes the port from foreman's own -p and --port flags" do
    expect(run_dev("-p", "4000").first).to eq("4000")
    expect(run_dev("--port=4100").first).to eq("4100")
  end
end
