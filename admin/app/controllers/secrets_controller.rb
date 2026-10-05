class SecretsController < ApplicationController
  # A filled field replaces the saved value; a blank one keeps it; a ticked
  # Remove deletes it.
  def update
    Secret.definitions.each do |definition|
      fields = params.dig(:secrets, definition.key) || {}
      if fields[:remove] == "1"
        Secret.where(key: definition.key).destroy_all
      elsif fields[:value].present?
        secret = Secret.find_or_initialize_by(key: definition.key)
        secret.update!(value: fields[:value], from_env: false)
      end
    end
    redirect_to edit_password_path, notice: "Secrets saved."
  end
end
