# frozen_string_literal: true

require "rails_helper"

# Two bugs met on this partial.
#
# #911: every key under `activity.actions` was written flat and dotted
# ("membership.created:"), which I18n's nested lookup never finds — so the
# `default:` fired on every row and the feed rendered humanized column values
# ("Membership.updated").
#
# #932: a deactivation and a reactivation are both recorded as
# `membership.updated`, so even with resolving keys they read as role changes.
# The row's own `changes` metadata is what distinguishes them.
RSpec.describe "activity_logs/_activity_log", type: :view do
  def render_row(action:, metadata: {}, actor: nil)
    log = ActivityLog.new(
      action: action,
      metadata: metadata,
      actor: actor,
      created_at: Time.current
    )
    render partial: "activity_logs/activity_log", locals: { activity_log: log }
    rendered
  end

  describe "membership.updated" do
    it "reads as a deactivation when discarded_at was set" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => { "discarded_at" => [ nil, 1.minute.ago.iso8601 ] } }
      )

      expect(html).to have_text("was deactivated")
      expect(html).not_to have_text("role")
    end

    it "reads as a reactivation when discarded_at was cleared" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => { "discarded_at" => [ 1.minute.ago.iso8601, nil ] } }
      )

      expect(html).to have_text("was reactivated")
    end

    it "reads as a role change when only the role moved" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => { "role" => [ "member", "admin" ] } }
      )

      expect(html).to have_text("had their role changed")
    end

    # #932: reactivate! can carry a role, and losing or regaining access is the
    # more consequential half of such a row.
    it "lets the status change win when the row carries both" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => {
          "role" => [ "member", "admin" ],
          "discarded_at" => [ nil, 1.minute.ago.iso8601 ]
        } }
      )

      expect(html).to have_text("was deactivated")
      expect(html).not_to have_text("had their role changed")
    end
  end

  it "renders the written string for membership.created" do
    expect(render_row(action: "membership.created")).to have_text("joined the workspace")
  end

  it "renders the written string for a non-membership action" do
    expect(render_row(action: "project.created")).to have_text("created a project")
  end

  it "still falls back to the humanized action for an unknown one" do
    expect(render_row(action: "widget.frobnicated")).to have_text("Widget.frobnicated")
  end

  # The #911 pin: the strings above must come from the locale file with no
  # `default:` masking a miss.
  it "sources its copy from resolvable locale keys" do
    expect(I18n.t("activity.actions.membership.created")).to eq("joined the workspace")
    expect(I18n.t("activity.actions.membership.updated")).to eq("had their role changed")
    expect(I18n.t("activity.actions.membership.deactivated")).to eq("was deactivated")
    expect(I18n.t("activity.actions.membership.reactivated")).to eq("was reactivated")
    expect(I18n.t("activity.actions.project.created")).to eq("created a project")
  end
end
