module Suspendable
  extend ActiveSupport::Concern

  # Raised by guarded lifecycle mutators when an owner attempts a transition
  # on a suspended (user-facing: "locked") record. Concern-level home so
  # Workspace and Project share one class (Project raises it via its
  # workspace's state).
  SuspendedError = Class.new(StandardError)

  included do
    scope :not_suspended, -> { where(suspended_at: nil) }
    scope :suspended,     -> { where.not(suspended_at: nil) }
  end

  def suspend!
    update!(suspended_at: Time.current)
  end

  def unsuspend!
    update!(suspended_at: nil)
  end

  def suspended?
    suspended_at.present?
  end
end
