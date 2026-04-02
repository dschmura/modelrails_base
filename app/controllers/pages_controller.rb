class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
  end

  def about
    flash.now[:notice] = "Profile updated successfully."
    flash.now[:success] = "Workspace created."
    flash.now[:info] = "Your session will expire in 5 minutes."
    flash.now[:alert] = "Storage usage is approaching the limit."
    flash.now[:error] = "Payment failed. Please update your billing details."
  end

  def privacy
  end

  def contact
  end
end
