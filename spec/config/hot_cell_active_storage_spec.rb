require "rails_helper"
require "hot_cell/test_cell"

# Active Storage through a real Hot Cell, forked from this process: every allowed image type thumbnails
# and analyzes there, and failures are classified. The cell image's own libvips is proven in its build.
RSpec.describe "Active Storage through a Hot Cell" do
  fixtures = {
    "image/png" => "sample.png", "image/jpeg" => "sample.jpg", "image/gif" => "sample.gif",
    "image/webp" => "sample.webp", "image/heic" => "sample.heic", "image/heif" => "sample.heif"
  }

  def boot_cell
    HotCell::TestCell.boot(name: HotCell::Cell.new("active_storage").name,
                           operations: -> { require "active_storage/hot_cell/server" })
  end

  def upload(name, content_type)
    ActiveStorage::Blob.create_and_upload!(io: Rails.root.join("spec/fixtures/files/hotcell", name).open,
                                           filename: name, content_type: content_type)
  end

  def thumbnail(blob) = blob.variant(resize_to_limit: [ 8, 8 ]).processed

  def cell_operations
    performed = []
    subscriber = ActiveSupport::Notifications.subscribe("perform.hot_cell") { |*, payload| performed << payload[:operation] }
    yield
    performed
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  before(:all) do
    @tmpdir = ENV["TMPDIR"]
    ENV["TMPDIR"] = "/tmp" if RUBY_PLATFORM.include?("darwin")
    @cell = boot_cell
    @saved = [ HotCell.root, ActiveStorage.variant_transformer, ActiveStorage.analyzers ]
    HotCell.root = @cell.socket_root
    ActiveStorage.variant_transformer = ActiveStorage::HotCell::Client::Transformers::Image::Vips
    ActiveStorage.analyzers = [ ActiveStorage::HotCell::Client::Analyzers::Image::Vips ]
  end

  after(:all) do
    HotCell.root, ActiveStorage.variant_transformer, ActiveStorage.analyzers = @saved
    @cell.stop
    @cell.cleanup
    ENV["TMPDIR"] = @tmpdir
  end

  it "covers every allowed image type" do
    expect(fixtures.keys).to match_array(ApplicationRecord::IMAGE_CONTENT_TYPES)
  end

  fixtures.each do |content_type, name|
    it "thumbnails #{content_type} through the cell" do
      blob = upload(name, content_type)
      variant = nil

      expect(cell_operations { variant = thumbnail(blob) }).to include("active_storage.transformers.image.vips")
      expect(variant.image.download.bytesize).to be > 0
    end
  end

  it "records width and height through the cell" do
    blob = upload("sample.png", "image/png")

    expect(cell_operations { blob.analyze }).to include("active_storage.analyzers.image.vips")
    expect(blob.metadata.slice("width", "height")).to eq("width" => 16, "height" => 16)
  end

  it "classifies broken bytes as a permanent failure" do
    expect { thumbnail(upload("truncated.png", "image/png")) }.to raise_error(HotCell::PermanentFailure)
  end

  it "classifies an unreachable cell as a transient failure" do
    stopped = boot_cell
    HotCell.root = stopped.socket_root
    stopped.stop

    expect { thumbnail(upload("sample.png", "image/png")) }.to raise_error(HotCell::TransientFailure)
  ensure
    HotCell.root = @cell.socket_root
    stopped&.cleanup
  end
end
