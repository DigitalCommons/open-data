# Keys for encrypted attributes (Secret#value), derived from secret_key_base,
# which persists across deploys in /app/data/secret_key_base on Cloudron.
# Losing that file makes saved secrets unreadable; they are then re-seeded
# from the environment or entered again on the Settings page.
Rails.application.config.after_initialize do
  generator = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base, iterations: 1000,
    hash_digest_class: OpenSSL::Digest::SHA256)
  derive = ->(purpose) { generator.generate_key("active_record_encryption.#{purpose}", 32).unpack1("H*") }
  ActiveRecord::Encryption.configure(
    primary_key: derive.call("primary_key"),
    deterministic_key: derive.call("deterministic_key"),
    key_derivation_salt: derive.call("key_derivation_salt")
  )
end
