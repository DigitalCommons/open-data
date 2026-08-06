class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :username, with: ->(u) { u.strip.downcase }
  validates :username, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true, on: :password_change

  # Nil until the seeded default password has been replaced.
  def must_change_password?
    password_changed_at.nil?
  end
end
