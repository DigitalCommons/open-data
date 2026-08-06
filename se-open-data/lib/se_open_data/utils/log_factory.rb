require 'logger'


module SeOpenData
  module Utils

    class LogHelper
      # Gets a hash of the arguments of a method.
      #
      # Intended to use with logging, to show method arguments.
      #
      # Call like this:
      #
      #     SeOpenData::Utils::LogHelper.dump_args(method(__method__), binding)
      #
      # @param _method The calling method instance
      # @param _binding The calling method's variable binding
      # @return a hash of argument names to their values.
      def self.dump_args(_method, _binding)
        Hash[
          _method.parameters.map.collect do |_, name|
            [name, _binding.local_variable_get(name)]
          end
        ]
      end
    end

    # Defines a configurable logging mechanism
    #
    # Designed to be simple to include, without needing to be
    # configured every time. Instead, it defines what we hope are
    # sensible defaults and optional configuration are permitted, to
    # fine tune these.
    #
    # Usage example, in a file foo/bar.rb:
    #
    #     require 'se_open_data/utils/log_factory'
    #
    #     Log = SeOpenData::Utils::LogFactory.default
    #     
    #     # ... in code somewhere later
    #        Log.debug "something happened"
    #
    # This will print something like this to STDERR:
    #
    #     D, [2020-05-15T17:17:19.830963 #12604] DEBUG -- foo/bar.rb: something happened
    #
    # See {default} for more details.
    class LogFactory

      # This gets a default logger instance, creating it if necessary,
      # observing externally defined configuration.  The {default}
      # factory method knows which file created it and names it
      # accordingly.
      #
      # Configuration can optionally be supplied via environment
      # variables with names prefixed with `SEA_LOG_`. Specifically:
      #
      # `SEA_LOG_LEVEL`: defines the log level. Should be one of:
      # - `debug`
      # - `info`
      # - `warn`
      # - `error`
      # - `fatal`
      # - `unknown`
      #
      # (Defaults to `warn`).
      #
      # `SEA_LOG_FILE`: should be the path to a file, relative to the
      # current working directory. (Default is to log to STDERR.)
      #
      # `SEA_LOG_CONTEXT`: specifies what to form of the file context
      # use to label loggers with. Specifically, can be:
      #
      # - `filename`: only the filename is used
      # - `rel`: the relative path is used
      # - `abs`: the absolute path is used
      # - `none`: no context label is printed
      #
      # (Defaults to `short`.)
      #
      # @return a new Logger instance
      def self.default
        
        # Set the progname
        caller_label =
          case ENV['SEA_LOG_CALLER']
          when 'filename'
            File.basename(caller_locations.first.path)
          when 'abs'
            File.absolute_path(caller_locations.first.path)
          when 'rel'
            caller_locations.first.path
          when 'none'
            nil
          else
            caller_locations.first.path
          end

        # Create the logger
        logger ||= Logger.new(
          ENV['SEA_LOG_FILE'] || STDERR,
          level: ENV['SEA_LOG_LEVEL'] || Logger::WARN,
        )

        logger.progname = caller_label if caller_label

        logger.debug("Created logger in #{caller_locations.first.path}")
        
        return logger
      end
      
    end
  end
end

