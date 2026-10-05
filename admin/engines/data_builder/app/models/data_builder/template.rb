module DataBuilder
  # A saved snapshot of the builder wizard's state, opaque to the server.
  class Template < ApplicationRecord
    validates :name, presence: true, uniqueness: true,
      format: { with: ApplicationController::ADMIN_ID }
    validates :state, presence: true
  end
end
