#!/bin/bash
set -eu

# Writable HOME so per-project `bundle install` can fall back to a user path
export HOME=/app/data

mkdir -p /app/data/storage /app/data/downloads /run/app/tmp /run/app/log

# Persistent secret key, generated on first start
if [[ ! -f /app/data/secret_key_base ]]; then
    openssl rand -hex 64 > /app/data/secret_key_base
fi
SECRET_KEY_BASE=$(cat /app/data/secret_key_base)
export SECRET_KEY_BASE

# Sync converter projects into the writable area. First start copies
# everything (some manual sources have committed original-data the converters
# need); later starts refresh code but never overwrite runtime data
# (original-data, generated-data, caches updated since).
mkdir -p /app/data/open-data
common_excludes=(--exclude /admin --exclude /Dockerfile --exclude /start.sh --exclude /CloudronManifest.json)
if [[ ! -f /app/data/open-data/.synced ]]; then
    rsync -a "${common_excludes[@]}" /app/code/ /app/data/open-data/
    touch /app/data/open-data/.synced
else
    rsync -a --update "${common_excludes[@]}" \
        --exclude '/*/original-data' --exclude '/*/generated-data' \
        /app/code/ /app/data/open-data/
fi

chown -R cloudron:cloudron /run/app /app/data

cd /app/code/admin

echo "=> Preparing database"
gosu cloudron:cloudron bundle exec rails db:prepare

echo "=> Seeding (idempotent: default user, new data sources)"
gosu cloudron:cloudron bundle exec rails db:seed

echo "=> Starting puma (Solid Queue in-process)"
exec gosu cloudron:cloudron bundle exec puma -C config/puma.rb
