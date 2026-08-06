class PasswordsController < ApplicationController
  skip_before_action :require_password_change

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    unless @user.authenticate(params[:current_password].to_s)
      flash.now[:alert] = "Current password is incorrect."
      return render :edit, status: :unprocessable_entity
    end

    if @user.authenticate(params[:password].to_s)
      flash.now[:alert] = "New password must be different from the current password."
      return render :edit, status: :unprocessable_entity
    end

    @user.assign_attributes(params.permit(:password, :password_confirmation))
    @user.password_changed_at = Time.current
    if @user.save(context: :password_change)
      redirect_to root_path, notice: "Password updated."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
