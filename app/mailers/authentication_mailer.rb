class AuthenticationMailer < ApplicationMailer
  def verification_email(authentication)
    @authentication = authentication
    @user = authentication.user
    @verification_url = email_verification_url(token: authentication.verification_token)

    mail(
      to: @user.email_address,
      subject: t("authentication_mailer.verification_email.subject")
    )
  end
end
