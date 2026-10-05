module DataBuilder
  # Signed-in users only, through the host app's controller (Authentication
  # concern). CSRF applies; the wizard sends the token.
  class ApplicationController < ::ApplicationController
    ADMIN_ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z/

    private

    def send_message(status, message)
      render json: { message: message }, status: status
    end

    def valid_id?(name)
      name.is_a?(String) && name.match?(ADMIN_ID)
    end
  end
end
