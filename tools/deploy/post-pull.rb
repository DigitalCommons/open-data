#!/bin/env ruby

# This installs the open-data application from git in a dedicated
# user account, and installs a systemd timer job which runs a script
# tools/deploy/cronjob with configurable environment variable
# definitions.  The job pulls changes from git before running this
# script.
#
# Prereqs:
#      - git
#      - pass
#      - ruby 2.6+ and bundler
#
# Configuration is via the environment. Environment variables
# are expected to be prefixed with 'SEOD_'.
#
# The only two mandatory ones are:
# - SEOD_USERNAME: the user we are installing as
# - SEOD_HOME_DIR: the user's home directory to install into
#
# Optional ones are:
# - SEOD_RUN_AT: defines when the systemd unit runs - systemd OnCalendar formats needed.
# - SEOD_WORKING_DIR: path to check out the application's git working directory
# - SEOD_EMAIL: one or more space-delimited email addresses to mail
#   notifications to Define this if you want to route job
#   notifications to an address(es) using the user's .forward
#   file. Note, will overwrite any existing .forward file.
# - SEOD_ENV_FILE: a file in which defines environment variables to be
#   passed to the application when run by systemd (using
#   EnvironmentFile=). It will be made unreadable to other non-root
#   users, and is intended for passwords and other potentially
#   sensitive information. Other variables such as build context
#   information can be put here too.
# - SEOD_ENV__*: variables matching this stem define environment
#   variables to define in the .env file and which are supplied to the
#   service. Typically these are passwords or API keys, but this file
#   can also be used to define other things, such as the name of an
#   alternative config file to use, the via SEOD_CONFIG variable. The
#   default otherise is to use 'local.conf' if present, else
#   'default.conf'. This means this is mainly needed for running in
#   production mode - the recommended name for a production config is
#   'production.conf'.
# - SEOD_CPU_QUOTA: the max CPU the service slice should allow
# - SEOD_MEMLIMIT: the max memory limit the service should allow
#
# Defaults for these are defined in the source code below.

require 'fileutils'
require 'open3'

######################################################################
# Classes and functions

# Loads environment variables, but allows default values to be supplied
#
# Note, all the names inferred from method calls are mapped to
# uppercase and prefixed with 'SEOD_' to get the corresponding
# environment variable.
class EnvConfig

  # Constructor.
  #
  # defaults: keyword options defining any default values to set
  def initialize(**defaults)
    @defaults = defaults
  end

  # Read a value from the environment or use a default.
  #
  # Throws an error if there is neither, unless suffixed with a question mark,
  # in which case return true if a value exists, false otherwise.
  def method_missing(symbol, *args)
    slug = symbol.to_s.sub(/[?]$/, '').to_sym # strip any trailing ?
    check_mode = slug != symbol # was there a ?
    throw 'invalid config value' unless slug =~ /^\w+$/
    name = "SEOD_#{slug.to_s.upcase}"

    if check_mode
      return ENV.has_key?(name) || @defaults.has_key?(slug)
    end
    
    if ENV.has_key? name
      ENV[name]
    else
      if @defaults.has_key? slug
        @defaults[slug]
      else
        raise "no variable for '#{slug}'"
      end
    end
  end

  # Returns a hash mapping environment variables matching a stem
  # to the appropriate values.
  def starting_with(stem)
    ENV.keys.filter do |key|
      key.start_with? 'SEOD_'+stem.upcase
    end.map do |key|
      skipchars = stem.size + 5
      [key[skipchars..], ENV[key]]
    end.to_h    
  end
end
  
# Run a command, capturing its output, printing it on failure.
def system!(cmd)
  out, status = Open3.capture2e(cmd)
  unless status.success?
    warn out
    abort "failed with #{status.exitstatus}: #{cmd}"
  end
  status.success?
end

# Install a file
#
# dest is a path or a writable IO stream
# content is the content to write
# if dest is a path,
# - perm, opt and mode are passed to File.write 
# - owner and group are used to set the ownership
def install_file(dest, content: '', perm: 0655, mode: 'w', opt: nil, owner: nil, group: nil)
  if dest.is_a? IO
    dest.write(content)
  else
    File.write(dest, content, perm: perm, mode: mode, opt: opt)
    if (owner and owner.is_a? String) or (group and group.is_a? String)
      FileUtils.chown(owner, group, dest)
    end
  end
end


######################################################################
# Value definitions

# Set the defaults
# Note: username and home_dir must be supplied externally! Others are optional.
c = EnvConfig.new(
  env_file: '.env',
  run_at: '*-*-* *:0/10',
  service_name: 'se_open_data',
  working_dir: 'working',
  cpu_quota: '80%',
  memlimit: '2G',
)

# Get the environment to set
env_vars = c.starting_with('ENV__')
             .map {|name, val| "#{name}=#{val}\n" }
             .join('')

# The absolute path to the .env file
env_file = File.join(c.home_dir, c.env_file)

# The absolute path to the working directory
working_dir = File.join(c.home_dir, c.working_dir)

# The absolute path to the systemd unit directory, and the systemctl
# commmand to use
service_path, systemctl =
              if c.home_dir == '/root' or c.home_dir == '/'
                ['/etc/systemd/system', 'systemctl']
              else
                [File.join(c.home_dir, '.config/systemd/user'), 'systemctl --user']
              end

service_file = File.join(service_path, "#{c.service_name}.service")
timer_file = File.join(service_path, "#{c.service_name}.timer")
slice_file = File.join(service_path, "#{c.service_name}.slice")

######################################################################
# logic

# Create mail .forward file for this user, if c.email defined
if c.email?
  email_list = c.email
                 .split
                 .map {|email| "#{email}\n" }
                 .join('')
  install_file "#{c.home_dir}/.forward",
               perm: 0644,
               content: email_list
end

# Create systemd .env file
install_file env_file,
             perm: 0600,
             content: env_vars

# Install the script for to be run via systemd
install_file "#{c.home_dir}/sync-and-run", perm: 0775, content: <<EOF
#!/bin/bash

# Synchronises the git working directory and runs the conversion
#
# Usage:
#  sync-and-run
#
# Assumes any passwords set in the environment

set -o errexit
set -o pipefail

export GIT_WORK_TREE="#{working_dir}"
export GIT_DIR="$GIT_WORK_TREE/.git"

# For local ruby gems
export PATH=$PATH:/usr/local/sbin:/usr/local/bin

# Remove all modifications bar ignored files
git clean -ffd

git fetch --all
git reset --hard origin/$(git symbolic-ref --short HEAD)

if ! "$GIT_WORK_TREE/tools/deploy/cronjob" ; then
  echo "FAILED ($?): $GIT_WORK_TREE/tools/deploy/cronjob"
  RC=1
fi

# Clean again so that ansible deploys not perturbed
git clean -ffd -e original-data/

exit $RC
EOF

install_file "#{c.home_dir}/post-sync", perm: 0775, content: <<EOF
#!/bin/bash

# Run following the sync service
#
# Usage:
#  post-sync <name of service>
#
# See also systemd.exec manpage for environment vars passed

set -o errexit
set -o pipefail


[[ "$SERVICE_RESULT" == "success" && "$EXIT_CODE" == "exited" ]] && exit

# If we get here, it wasn't success

#{systemctl} status $1 | mail -s "FAILED ($SERVICE_RESULT/$EXIT_CODE): $1" #{c.username}
EOF

# Install systemd se_open_data.service defining how to run our job
FileUtils.mkdir_p(service_path)
install_file service_file, perm: 0664, content: <<EOF
# Run #{c.service_name} regeneration process
[Unit]
Description=Rebuilds the datasets in #{working_dir}
Wants=#{c.service_name}.timer

[Service]
Type=exec
User=#{c.username}
Group=#{c.username}
WorkingDirectory=#{c.home_dir}
ExecStart=#{File.join c.home_dir, 'sync-and-run'}
ExecStopPost=-#{File.join c.home_dir, 'post-sync'} %n
ProtectSystem=strict
ReadWritePaths=/var/www /var/tmp /var/spool /tmp #{working_dir}
EnvironmentFile=#{env_file}

[Install]
WantedBy=multi-user.target
EOF

# Install systemd se_open_data.timer defining when to run our job
install_file timer_file, perm: 0664, content: <<EOF
[Unit]
Description=Runs the #{c.service_name}.service periodically
Requires=#{c.service_name}.service

[Timer]
Unit=#{c.service_name}.service
OnCalendar=#{c.run_at}

[Install]
WantedBy=timers.target
EOF

install_file slice_file, perm: 0664, content: <<EOF
[Unit]
Description=Limited resources slice for #{c.service_name}
DefaultDependencies=no
Before=slices.target

[Slice]
CPUQuota=#{c.cpu_quota}
MemoryLimit=#{c.memlimit}
EOF

# Enable timer and service
throw 'failed to enable service' unless system! <<EOF
#{systemctl} daemon-reload &&
#{systemctl} enable #{c.service_name}.timer &&
if #{systemctl} is-active --quiet #{c.service_name}; then
   #{systemctl} restart #{c.service_name}.timer
else
   #{systemctl} start #{c.service_name}.timer
fi
EOF
