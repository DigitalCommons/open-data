# Deployment

The app is packaged as a Cloudron custom app. The repo root holds the
`Dockerfile`, `CloudronManifest.json` and `start.sh`; the image contains
the admin app and every converter directory. `deploy.sh` builds the image
and installs or updates the app on a Cloudron of your choice.

## What you need

- A Cloudron you are an admin of, referred to below as `my.example.com`.
- A container registry the Cloudron can pull from: the Cloudron Container
  Registry app on the same Cloudron, Docker Hub, or any other registry.
  Referred to below as `registry.example.com`.
- Cloudron CLI 9 or later on your machine:

```
npm install -g cloudron
cloudron --version
```

## One-time login

```
cloudron login my.example.com
cloudron builder login registry.example.com
```

The builder login takes the registry's username and password. For the
Cloudron Container Registry app that is your Cloudron username and an App
password from the dashboard (Account > App Passwords), not your account
password.

## Deploying with deploy.sh

From the repo root:

```
cd /path/to/open-data
./deploy.sh
```

It asks for:

- Cloudron server: the dashboard domain, `my.example.com`
- Container registry: `registry.example.com`
- Image repository in the registry: `opendata` unless you want another name
- App location: the domain the app will be served on, `data.example.com`
- Image tag: defaults to the version in `CloudronManifest.json`

Then it runs the build, checks whether an app already exists at the
location, and installs or updates it. The answers are saved in
`.deploy.conf` (git-ignored) and offered as defaults next time.

Every answer can be given as an environment variable instead, which skips
its prompt. With no terminal, unset answers that have a default use it and
any other unset answer stops the script. This is the form to use from CI:

```
DEPLOY_SERVER=my.example.com DEPLOY_REGISTRY=registry.example.com DEPLOY_REPOSITORY=opendata DEPLOY_LOCATION=data.example.com ./deploy.sh
```

Set `DEPLOY_NO_BACKUP=1` to update without a backup first.

## Releasing a new version

1. Bump `version` in `CloudronManifest.json`. The version shows in the app
   header.
2. Run `./deploy.sh`.

The Cloudron keeps the previous image, so a failed update can be rolled
back from the dashboard.

## The same steps by hand

```
cd /path/to/open-data
cloudron builder build --repository opendata --tag 1.2.3
cloudron --server my.example.com install --location data.example.com --last-build
```

For an update:

```
cloudron --server my.example.com update --app data.example.com --last-build
```

`--repository` is worth passing every time: the builder remembers the last
repository used in a directory, and a stale one would push to the wrong
registry. `--server` is a global option and goes before the subcommand.

## First start

1. Open `https://data.example.com` and sign in as `mykomaps` with password
   `admin`. The app insists on a new password before anything else.
2. On Settings, enter the secrets the converters need, or set them as
   environment variables before the first start:

```
cloudron --server my.example.com env set --app data.example.com PASSWORD__GEOAPIFYAPI_TXT=...
cloudron --server my.example.com restart --app data.example.com
```

   Variables are saved into the app on start where nothing is saved yet;
   after that the Settings page is the source of truth.
3. Every source appears disabled unless it is listed in `LEGACY_LIVE` in
   `app/models/data_source.rb`. Give each one a schedule and enable it.

## Inside the container

Everything the app writes is under `/app/data`, which Cloudron backs up:

- `/app/data/open-data`: the converter directories, synced from the image
  on each start. Code is refreshed; `original-data`, `generated-data` and
  caches are kept.
- `/app/data/downloads`, `/app/data/builds`: archives
- `/app/data/storage`: SQLite databases
- `/app/data/secret_key_base`: generated on first start. Losing it makes
  saved secrets unreadable; they are then re-seeded from the environment or
  entered again on Settings.

Useful commands:

```
cloudron --server my.example.com logs --app data.example.com --lines 100
cloudron --server my.example.com exec --app data.example.com
```

Inside the container the app runs as `cloudron` from `/app/code/admin`:

```
cd /app/code/admin
export SECRET_KEY_BASE=$(cat /app/data/secret_key_base)
gosu cloudron:cloudron env HOME=/app/data SECRET_KEY_BASE=$SECRET_KEY_BASE bundle exec rails runner 'puts DataSource.enabled.count'
exit
```

The manifest asks for 2 GB of memory and uses `/up` as the health check.
Puma runs Solid Queue in-process, so there is no separate worker.
