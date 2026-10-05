class UsernamesController < ApplicationController
  # Changing the username needs the current password, so an unattended
  # session cannot be used to take the account over.
  def update
    @user = Current.user

    unless @user.authenticate(params[:current_password].to_s)
      flash.now[:alert] = "Current password is incorrect."
      return render "passwords/edit", status: :unprocessable_entity
    end

    if @user.update(username: params[:username].to_s)
      redirect_to edit_password_path, notice: "Username updated."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      @user.restore_attributes
      render "passwords/edit", status: :unprocessable_entity
    end
  end
end
