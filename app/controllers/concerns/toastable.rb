module Toastable
  extend ActiveSupport::Concern

  private

  def toast_stream(type, message)
    target = %w[notice success info].include?(type) ? "toast-pills" : "toast-cards"
    partial = %w[notice success info].include?(type) ? "shared/toast_pill" : "shared/toast_card"
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
