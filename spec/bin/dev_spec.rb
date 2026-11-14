# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

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

  def run_dev(*args, env: {})
    path = "#{@dir.join('stubs')}:#{ENV.fetch('PATH')}"
    output, status = Open3.capture2e({ "PATH" => path, "PORT" => nil, "DEV_SERVER_PORT" => nil }.merge(env),
                                     Rails.root.join("bin/dev").to_s, *args, chdir: @dir.to_s)
    expect(status).to be_success, output
    exported, foreman_args = output.lines.map(&:strip)
    [ exported.delete_prefix("DEV_SERVER_PORT="), foreman_args ]
  end

  it "exports the web port as DEV_SERVER_PORT and starts foreman on it" do
    expect(run_dev).to eq([ "3000", "start -f Procfile.dev --port 3000" ])
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
