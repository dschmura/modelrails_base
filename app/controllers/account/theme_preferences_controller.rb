module Account
  class ThemePreferencesController < ApplicationController
    def update
      preferences = Current.user.preferences || Current.user.create_preferences!
      preferences.update!(theme: params[:theme] || theme_params[:theme])

      respond_to do |format|
        format.json { render json: { theme: preferences.theme }, status: :ok }
        format.turbo_stream
        format.html { redirect_to edit_account_profile_path, notice: t(".success") }
      end
    rescue ArgumentError
      respond_to do |format|
        format.json { render json: { error: t(".invalid_theme") }, status: :unprocessable_entity }
        format.html { redirect_to edit_account_profile_path, alert: t(".invalid_theme") }
      end
    end

    private

    def theme_params
      params.require(:user_preferences).permit(:theme)
    end
  end
end
