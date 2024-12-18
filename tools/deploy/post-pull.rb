#!/bin/env ruby

# We need an appropriate ruby version: 2.6 or newer

# Prereqs:
#      - git
#      - pass
#      - ruby & bundler
# FIXME ensure errors on failures checked

# ---
# This installed the open-data application from git in a
# dedicated user account, and installs a systemd timer job which runs a script
# tools/deploy/cronjob with configurable environment variable
# definitions.  The job pulls changes from git before running
# this script.
require 'fileutils'
require 'open3'

class EnvConfig
  def initialize(**defaults)
    @defaults = defaults
  end
  
  def method_missing(symbol, *args)
    slug = symbol.to_s.sub(/!$/, '').to_sym # strip any trailing !
    force = slug != symbol # was there a !?
    throw "invalid config value" unless slug =~ /^\w+$/
    name = "SEOD_#{slug.to_s.upcase}"
    if ENV.has_key? name
      ENV[name]
    else
      if @defaults.has_key? slug
        @defaults[slug]
      else
        if force
          raise "no variable for '#{slug}'"
        else
          warn "no variable for '#{slug}'"
        end
        return nil
      end
    end
  end
  
  def starting_with(stem)
    ENV.keys.filter do |key|
      key.start_with? "SEOD_"+stem.upcase
    end.map do |key|
      [key, ENV[key]]
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

c = EnvConfig.new(
  username: 'root',
  home_dir: '/root',
  env_file: '.env',
  service_name: 'se_open_data',
  working_dir: 'working',
  repo_version: 'master',
)


# The name of the user account to create and install the application under
#c.username = 'seopendata'

# The home directory of the user. 
#home_dir = "/home/#{c.username}" # FIXME

## Any supplemental group the account should belong to
## (Typically so they can write to certain locations without sudo)
#c.supp_group = 'www-data'

# These configure when the systemd unit runs - systemd OnCalendar formats needed.
#c.run_at = '*-*-* *:6:00'

# The path of the git working directory in which the application is checked out

# This is a file in which defines environment variables to be passed
# to the application when run by systemd (using EnvironmentFile=). It
# will be made unreadable to other non-root users, and is intended for
# passwords and other potentially sensitive information. Other
# variables such as build context information can be put here too.
#c.env_file = "#{c.home_dir}/.env"

# This is a dictionary of names/values of environment variables to
# define in the file c.env_file. Names must consist of
# alphanumeric or underscore characters only.
#
# This file can also be used to define the name of an alternative
# config file to use, the via SEOD_CONFIG variable. The default
# otherise is to use 'local.conf' if present, else
# 'default.conf'. This means this is mainly needed for running in
# production mode - the recommended name for a production config is
# 'production.conf'.

pass_env_vars = c.starting_with('PASS__')

working_dir = File.join(c.home_dir!, c.working_dir!)

# FIXME get these from somewhere

# Where to write Gem configs
#c.gem_path = "#{c.home_dir}/.gem"

# The URL of the git repository to check out
#c.repo = 'https://github.com/DigitalCommons/open-data.git'

# The branch of the git repository to check out
#c.repo_version = 'master'

# Define this if you want to route job notifications to an address(es)
# using the user's .forward file. Note, will overwrite any existing
# .forward file.
# Should be a list of email addresses.
# c.email = ['somewhere@example.com']

#service_name = "se_open_data"
#SYSTEMD_UNIT="$USERDIR/.config/systemd/user/mykomap-backend.service"
service_path, systemctl_flags =
              if c.home_dir == "/root" or c.home_dir == "/"
                ['/etc/systemd/system', ""]
              else
                [File.join(c.home_dir!, '.config/systemd/user'), "--user"]
              end

service_file = File.join(service_path, "#{c.service_name}.service")
timer_file = File.join(service_path, "#{c.service_name}.timer")
slice_file = File.join(service_path, "#{c.service_name}.slice")

#---


# Create mail .forward file for this user, if c.email defined
if c.email
  forward_file = "#{c.home_dir}/.forward"
  File.write(
    forward_file,
    c.email
      .map {|it| it+"\n" }
      .join("")
  )
  File.chmod 0644, forward_file
end

# Create systemd .env file
env_file = File.join(c.home_dir!, c.env_file!)
File.write(
  env_file,
  pass_env_vars
    .map {|name, val| "#{name}=#{val}\n" }
    .join("")
)
File.chmod(0600, env_file)
  
  
# Clone git repo
# (FIXME should be done already)

# name: Enable group access to working directory (for maintenance) FIXME maybe not necc
# system! <<EOF
# chmod -R g+srw #{working_dir} &&
# find #{working_dir} -type d -print0 | xargs -0 chmod g+x
# EOF

# Find.find(working_dir) do |path|
#   if File.directory?
#     FileUtils.chmod "+x", path
#   else
#     FileUtils.chmod "g+srw", path
#   end
# end

# Installs a file
# dest is a path or a writable IO stream
# content is the content to write
# if dest is a path,
# - perm, opt and mode are passed to File.write 
# - owner and group are used to set the ownership
def install_file(dest, content: "", perm: 0655, mode: "w", opt: nil, owner: nil, group: nil)
  if dest.is_a? IO
    dest.write(content)
  else
    File.write(dest, content, perm: perm, mode: mode, opt: opt)
    if (owner and owner.is_a? String) or (group and group.is_a? String)
      FileUtils.chown(owner, group, dest)
    end
  end
end

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

systemctl status $1 | mail -s "FAILED ($SERVICE_RESULT/$EXIT_CODE): $1" #{c.email&.join(' ') || 'root'}
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
User=#{c.username!}
Group=#{c.username!}
WorkingDirectory=#{c.home_dir!}
ExecStart=#{File.join c.home_dir!, 'sync-and-run'}
ExecStopPost=-#{File.join c.home_dir!, 'post-sync'} %n
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
CPUQuota=80%
MemoryLimit=2G
EOF

# Enable timer
# FIXME
throw "failed to enable service" unless system! <<EOF
systemctl #{systemctl_flags} daemon-reload &&
systemctl #{systemctl_flags} enable #{c.service_name}.timer &&
if systemctl #{systemctl_flags} is-active --quiet #{c.service_name}; then
   systemctl #{systemctl_flags} restart #{c.service_name}.timer
else
   systemctl #{systemctl_flags} start #{c.service_name}.timer
fi
EOF
