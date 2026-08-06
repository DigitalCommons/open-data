
require 'open3'

module SeOpenData
  module Utils
    # Facilitates reading passwords from an encrypted password store.
    #
    # Specifically in the case of SEA, this:
    #
    # https://github.com/SolidarityEconomyAssociation/password-store/
    #
    # This uses `pass`, the password store. See:
    #
    # https://www.passwordstore.org/
    #
    # What this actually means in practice is that:
    # - You need to have `pass` installed
    # - You need to have the `pasword-store` repository checked out
    #   (from https://github.com/SolidarityEconomyAssociation/password-store/)
    # - This needs to be in a directory adjacent to `open-data`'s working directory
    # - *Or*, you must set the path to it in the constructor
    # - *Or*, you must define it with the `PASSWORD_STORE_DIR` environment variable
    # - And you need to have followed the instructions in the password-store repository
    #   for setting up yourself with a GPG key to get access to the passwords.
    #   (See link above)
    #
    # This is not advised, but if you don't want to (or can't) use
    # `pass` then you can enable a feature to fall back to environment
    # variables. Note, THESE ARE NOT ENCRYPTED! The intention is just
    # to give some people who haven't gotten to grips with GPG a
    # little breathing space to get things done. But please, take the
    # time to learn to use it, because unencrypted and/or hardwired
    # passwords floating around in repositories or file systems are
    # something to avoid.
    #
    # Anyway, you can do this by instantiating this class with the
    # `use_env_vars` flag enabled, like this:
    #
    #     SeOpenData::Utils::PasswordStore.new use_env_vars: true
    #
    # The environment variables are expected begin with the prefix
    # `PASSWORD__`, followed by the upper-cased path (as passed to
    # get) with invalid characters replaced with underscores (so that
    # includes anything not alphanumeric or underscore).
    #
    # i.e. A path `some/path/foo.txt` will result in checking for a
    # variable `PASSWORD__SOME_PATH_FOO_TXT`. If it is not defined, we
    # fall back to using `pass`.
    #
    class PasswordStore

      # Initialise a new instance.
      #
      # @param use_env_vars [Boolean] Set this to true to look for
      # passwords in environment variables, as described in the
      # overview.
      def initialize(use_env_vars: false)
        @use_env_vars = !!use_env_vars
      end

      # Indicates whether this instance checks environment variables
      # for passwords, as described in the overview.
      #
      # @return [Boolean] true if it checks the environment, false if
      # it doesn't.
      def use_env_vars?
        @use_env_vars
      end

      # Get a password from its file path in the store, if it exists.
      #
      # @param path [String] The password's path in the password
      # store.  (Ultimately just a string which is a valid file path).
      #
      # @return The decrypted password, if found.  Note, this will
      # only get the first line, with the trailing newline character
      # stripped.
      #
      # @raise [RuntimeError] if no password could be found, either because
      # it isn't defined, or `pass` failed in some other way
      def get(path)
        if use_env_vars?
          # Try looking in the environment first
          var_name = 'PASSWORD__'+path.upcase.tr('^A-Z0-9_', '_')
          if env.has_key?(var_name)
            return env[var_name]
          end

          # Fall back to using pass
        end
        
        stdout, stderr, status = capture3('pass', 'show', path)
        if status != 0
          raise "failed to get password for #{path}: #{stderr}"
        end
        
        return stdout.lines.first.chomp
      end


      protected

      # This method is used to get ENV in a way which can be stubbed
      # in tests by overriding it.
      def env
        ENV
      end

      # This method is used to capture a command's stdout/stderr and
      # return value, in a way which can ben stubbed in tests by
      # overriding it.
      def capture3(*args)
        Open3.capture3(*args)
      end
    end
  end
end
