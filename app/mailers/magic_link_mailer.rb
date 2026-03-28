class MagicLinkMailer < ApplicationMailer
  def sign_in_link(user)
    @user = user
    @link_url = magic_link_session_url(token: user.magic_link_token)

    mail(
      to: user.email_address,
      subject: t("magic_link_mailer.sign_in_link.subject")
    )
  end

  def registration_link(email, token)
    @email = email
    @link_url = magic_link_registration_url(token: token)

    mail(
      to: email,
      subject: t("magic_link_mailer.registration_link.subject")
    )
  end
end
