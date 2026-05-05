# frozen_string_literal: true

class NotificationPolicy < ApplicationPolicy
  def update?
    record.recipient_id == user.id && record.recipient_type == "User"
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(recipient: user)
    end
  end
end
