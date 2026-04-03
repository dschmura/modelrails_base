module Toastable
  extend ActiveSupport::Concern

  private

  def toast_stream(type, message)
    type_config = Rails.application.config.toasts[:types][type.to_sym]
    tier = type_config&.dig(:tier) || :card
    target = tier == :pill ? "toast-pills" : "toast-cards"
    partial = tier == :pill ? "shared/toast_pill" : "shared/toast_card"
    turbo_stream.append(target, partial: partial, locals: { type: type, message: message })
  end

  def success_toast(message)
    toast_stream("success", message)
  end

  def notice_toast(message)
    toast_stream("notice", message)
  end

  def info_toast(message)
    toast_stream("info", message)
  end

  def error_toast(message)
    toast_stream("error", message)
  end

  def warning_toast(message)
    toast_stream("alert", message)
  end
end
