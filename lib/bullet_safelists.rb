# frozen_string_literal: true

# Shared by development and test, loaded by require_relative before Zeitwerk is active. Each entry's
# trade-off: /docs/developer/testing (Bullet safelists live in one file).
module BulletSafelists
  module_function

  def apply
    apply_unused_eager_loading
    apply_n_plus_one
  end

  # --- Unused eager loading -------------------------------------------------

  def apply_unused_eager_loading
    # Framework false positive: ActiveStorage's bulk touch includes :record but never reads it.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "ActiveStorage::Attachment", association: :record)

    # The notifications index preloads event.record for every subtype; this one's message never reads it.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "SignInFromNewDeviceNotifier", association: :record)

    # Members index: unused on pages that render no invitation rows (#124/#125).
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Invitation", association: :role)

    # Sidebar switcher's owner-avatar fallback: conditional per row, so any leg can go unused.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :user)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :role)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "User", association: :avatar_attachment)

    # Workspaces index: Bullet misreads this preload as redundant against the join it sorts by.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :workspace)
  end

  # --- N+1 query ------------------------------------------------------------

  def apply_n_plus_one
    # Empty on purpose (#1054): a safelist is global and would hide a real N+1 on every other page.
    # The notifications index uses ApplicationNotifier.preload_records instead.
  end
end
