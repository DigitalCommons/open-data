#!/usr/bin/env bash
# Build the image and install or update the app on a Cloudron.
#
# Asks for the Cloudron server, the container registry, the image
# repository and the app location, remembering the answers in .deploy.conf
# (git-ignored) for next time. Each answer can also be given as an
# environment variable, which skips the prompt:
#
#   DEPLOY_SERVER      Cloudron dashboard domain, e.g. my.example.com
#   DEPLOY_REGISTRY    container registry the builder pushes to
#   DEPLOY_REPOSITORY  image repository within the registry, e.g. opendata
#   DEPLOY_LOCATION    app domain, e.g. data.example.com
#   DEPLOY_TAG         image tag (default: version in CloudronManifest.json)
#   DEPLOY_NO_BACKUP=1 update without taking a backup first
#   DEPLOY_CONFIG      where answers are saved (default: ./.deploy.conf)
#
# Needs Cloudron CLI 9 or later, logged in to the server and the registry:
#   cloudron login my.example.com
#   cloudron builder login registry.example.com
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"

config="${DEPLOY_CONFIG:-$root/.deploy.conf}"
manifest_version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' CloudronManifest.json)"

# Saved answers are defaults; variables already in the environment win.
if [[ -f "$config" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    [[ -z "${!key:-}" ]] && declare "$key=$value"
  done < "$config"
fi

# ask VAR "Prompt" [default]
# Prompts for VAR when it is unset. Without a terminal the default is used,
# and an answer with no default is an error, so a scripted run never hangs
# on a prompt.
ask() {
  local var="$1" prompt="$2" default="${3:-}" value
  if [[ -n "${!var:-}" ]]; then
    return
  fi
  if [[ ! -t 0 ]]; then
    if [[ -n "$default" ]]; then
      declare -g "$var=$default"
      return
    fi
    echo "$var is not set and there is no terminal to ask on." >&2
    exit 1
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value
    value="${value:-$default}"
  else
    while [[ -z "${value:-}" ]]; do
      read -r -p "$prompt: " value
    done
  fi
  declare -g "$var=$value"
}

ask DEPLOY_SERVER "Cloudron server (dashboard domain)"
ask DEPLOY_REGISTRY "Container registry"
ask DEPLOY_REPOSITORY "Image repository in the registry" "opendata"
ask DEPLOY_LOCATION "App location (domain)"
ask DEPLOY_TAG "Image tag" "$manifest_version"

cat > "$config" <<CONF
DEPLOY_SERVER=$DEPLOY_SERVER
DEPLOY_REGISTRY=$DEPLOY_REGISTRY
DEPLOY_REPOSITORY=$DEPLOY_REPOSITORY
DEPLOY_LOCATION=$DEPLOY_LOCATION
CONF

run() {
  echo "+ cloudron $*"
  cloudron "$@"
}

# --repository every time: the builder remembers the last repository per
# directory, and a stale one would push to the wrong registry.
run builder build --repository "$DEPLOY_REPOSITORY" --tag "$DEPLOY_TAG"

# --server goes before the subcommand (it is a global option).
if run --server "$DEPLOY_SERVER" list | grep -q -- "$DEPLOY_LOCATION"; then
  update_args=(--app "$DEPLOY_LOCATION" --last-build)
  [[ -n "${DEPLOY_NO_BACKUP:-}" ]] && update_args+=(--no-backup)
  run --server "$DEPLOY_SERVER" update "${update_args[@]}"
else
  run --server "$DEPLOY_SERVER" install --location "$DEPLOY_LOCATION" --last-build
fi

echo "Deployed $DEPLOY_REPOSITORY:$DEPLOY_TAG to https://$DEPLOY_LOCATION"
