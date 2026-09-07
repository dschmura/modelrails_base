# frozen_string_literal: true

require "rails_helper"

# An email-provider authentication's uid is the user's id (#903). It used to be
# a second copy of users.email_address, kept in step by three writers — and the
# third, `authentications.email.update_all(uid: …)`, skipped the uid uniqueness
# validator on its way past. One fact in two columns, and under deterministic
# encryption the two columns held identical bytes for the same address, so a
# leaked dump joined them.
#
# `Authentication#assign_email_uid` is now the only writer, and it fills blanks
# only. Anything that hands the column an address puts the mirror back — in the
# app, in a seed, or in a fixture that then teaches the next author the old
# shape. This is the issue's own grep, standing.
#
# db/migrate is exempt: the data migration's `down` restores the mirror on
# purpose, because that is the way back to the release before #903.
RSpec.describe "Code smell: nothing writes an address into authentications.uid" do
  # `uid: …email_address` (keyword), `uid = …email_address` (assignment),
  # `uid { …email_address }` (factory block), and update_all in any spelling —
  # update_all bypasses validations, so it never writes this column again.
  def patterns
    {
      /\buid:\s*\S*email_address/ => "uid: … email_address",
      /\buid\s*=\s*\S*email_address/ => "uid = … email_address",
      /\buid\s*\{\s*\S*email_address/ => "uid { … email_address }",
      /update_all\(\s*uid:/ => "update_all(uid:)"
    }
  end

  def scanned_files
    (Dir[Rails.root.join("app/**/*.rb")] +
      Dir[Rails.root.join("app/**/*.erb")] +
      Dir[Rails.root.join("lib/**/*.rb")] +
      Dir[Rails.root.join("db/*.rb")] +
      Dir[Rails.root.join("spec/**/*.rb")]).sort - [ __FILE__ ]
  end

  it "writes no address into an email authentication's uid, anywhere" do
    offenders = scanned_files.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, i|
        label = patterns.find { |pattern, _| line.match?(pattern) }&.last
        next unless label

        "#{Pathname(file).relative_path_from(Rails.root)}:#{i + 1}: #{label} — #{line.strip}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      An email authentication's uid is the user's id (#903), assigned by
      Authentication#assign_email_uid. These put the address back:

      #{offenders.join("\n")}

      Create the row without a uid and let the model fill it.
    MSG
  end
end
