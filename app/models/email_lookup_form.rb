# Form object for the smart sign-in lookup flow's invalid-email render path.
# Uses ActiveModel::Model to provide the standard `errors` API that
# TailwindFormBuilder expects, so the view can render via `form_with model:`
# and inherit auto-applied error classes, ARIA attributes, and inline error
# messages without re-implementing them in the template.
class EmailLookupForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email_address, :string

  # Both presence and format use the same user-facing message so blank email,
  # missing email, and malformed email all render the unified "please enter a
  # valid email address" notice. (Without the custom message on presence, blank
  # input would surface the default "can't be blank" string and the test
  # assertion at spec/requests/sessions_spec.rb would diverge.)
  EMAIL_LOOKUP_INVALID_MESSAGE = ->(_object, _data) { I18n.t("sessions.lookup.invalid_email") }

  validates :email_address,
            presence: { message: EMAIL_LOOKUP_INVALID_MESSAGE },
            format: { with: User::EMAIL_FORMAT, message: EMAIL_LOOKUP_INVALID_MESSAGE }
end
