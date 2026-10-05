# Default admin user; password must be changed on first sign-in
# (password_changed_at stays nil until the user does so).
User.find_or_create_by!(username: "mykomaps") do |user|
  user.password = "admin"
end

# Register every source directory in the repo as a data source.
DataSource.sync_from_repo!

# Group the sources into projects.
Project.sync_from_file!

# Save secrets found in the environment where none is saved yet.
Secret.seed_from_env!
