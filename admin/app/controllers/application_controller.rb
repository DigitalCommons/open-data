class ApplicationController < ActionController::Base
  include Authentication
  before_action :require_password_change

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  # Users still on the seeded default password may go nowhere else.
  def require_password_change
    return unless authenticated? && Current.user&.must_change_password?
    redirect_to main_app.edit_password_path, alert: "You must change the default password before continuing."
  end
end
