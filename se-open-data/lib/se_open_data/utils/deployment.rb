require 'pathname'
require 'open3'
require 'tmpdir'
require 'se_open_data/utils/log_factory'

module SeOpenData
  module Utils

    # Hides the messy details of the deployment process.
    #
    # 
    class Deployment
      # Create a log instance
      Log = SeOpenData::Utils::LogFactory.default
 
      # Performs a deployment: a recursive copy of a directory to some
      # destination directory, which is created if not present.
      #
      # @param from_dir [String] path the directory to copy from on
      # the local machine. Relative paths are relative to {Dir.pwd}
      # @param to_dir [String] path of the directory to copy to.
      # Relative paths are relative to the remote user's home directory,
      # or if {to_server} is omitted, to {Dir.pwd} on the local machine.
      # @param to_server [String] `rsync` hostname URI of the server to copy to. As such
      # it may be preceeded by the remote account name, delimited with an @, etc. It can
      # be omitted, in which case the transfer is to the local filesystem.
      # @param ensure_present [String] path on the remote machine which must
      # exist in order for anything to be deployed. This can only be used in situations
      # when `--rsync-path` can be used - so not with rsync servers or when the ssh
      # login command has been mandated by the remote ssh config.
      # @param owner [String] the name of a user account which should own the deployed files.
      # This can only be set if the remote account has permissions to do this. Requires
      # `rsync` v3.1.1 or above.
      # @param group [String] the name of a user group which should own the deployed files.
      # This can only be set if the remote account has permissions to do this. Requires
      # `rsync` v3.1.1 or above.
      # @param exclude [String,#collect] if supplied, used to set rsync's `--exclude` option.
      # A string is interpreted as a single exclusion rule; anything else is expanded with
      # #collect into a series of rules.
      # @param verbose [Boolean] if true, show the rsync verbose output. Otherwise, try and stay
      # silent if things go well.
      # @raise ...FIXME
      def deploy(from_dir:, to_dir:, to_server: nil, ensure_present: nil, exclude: nil,
                 owner: nil, group: nil, verbose: false)
        Log.debug "deploy #{SeOpenData::Utils::LogHelper.dump_args(method(__method__), binding)}"

        args = %w(-rltgoDz)

        if !owner.nil?
          args.push "--usermap=*:#{owner}"
        end
        
        if !group.nil?
          args.push "--groupmap=*:#{group}"
        end

        if verbose
          args.push '-v'
        else
          args.push '-q'
          args.push '--no-motd'
        end

        # Make sure there's a trailing slash on these, for rsync,
        # they're significant!
        from_dir = File.join(from_dir, '')
        to_dir = File.join(to_dir, '')

        # Check the ensure_present path is present
        if !ensure_present.nil?
          # Test for the existance of this path.
          cmd = ['rsync', '-n', '/dev/null', to_dir]
          Log.debug "#{cmd}"
          stdout, stderr, status = capture3(*cmd)
          raise RuntimeError, "required directory absent: #{ensure_present}" unless status == 0
        end
        
        # Ensure the directory exists. We try to a) avoid using
        # anything but rsync, b) avoid tricks which won't work with
        # rsync servers or ssh config mandated login commands, or
        # rsync to the local filesystem.
        if to_server.nil?
          begin
            # Local filesystem. Set the ownership on parent dirs too
            Pathname.new(to_dir).descend do |path|
              if !Dir.exist? path
                Log.debug "creating #{path} #{owner}:#{group}"
                Dir.mkdir path
                FileUtils.chown owner, group, path
              end
            end
          rescue => err
            raise RuntimeError, "failed to create local target #{to_dir}: #{err.message}"
          end
        else
          # Make a directory to rsync
          Dir.mktmpdir do |dir|
            path = File.join(dir, to_dir)
            FileUtils.mkdir_p path
            
            remote = to_server + ':'
            remote += '/' if Pathname.new(to_dir).absolute?

            # And rsync it
            cmd = ['rsync', *args, File.join(dir, ''), remote]
            Log.debug "#{cmd}"
            stdout, stderr, status = capture3(*cmd)
            # This may error out, but succeed. ignore errors.
          end
          

          # Prepend the server on to_dir
          to_dir = to_server+':'+to_dir
        end

        args.push '--delete'
        
        if !exclude.nil?
          if exclude.is_a? String
            args.push %(--exclude=#{exclude})
          else
            args.concat exclude.collect {|it| %(--exclude=#{it}) }
          end
        end
        
        # This command does the actual copy
        cmd = %w(rsync).append(*args, from_dir, to_dir)

        Log.debug "#{cmd}"
        stdout, stderr, status = capture3(*cmd)
        unless status == 0
          warn stdout
          raise "deployment command failed: #{cmd}\n#{stderr}"
        end

        if verbose
          puts stdout
        end
      end

      
      private
      
      # Escape double quotes in a string
      def esc(string)
        string.gsub('"', '\\"').gsub('\\', '\\\\')
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

