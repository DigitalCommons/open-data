# Developing the admin app

This guide is for a developer who knows the basics of Rails and wants to
change the admin app. It covers how the code is laid out, how a request
and a background run move through it, how the tests work and how to make
common changes. Setup commands are in the [admin README](../README.md).

## The stack

- Rails 8.1 with the default Hotwire set: Turbo, Stimulus through
  importmap, Propshaft for assets, Tailwind for the stylesheet.
- SQLite for all four databases (primary, cache, queue and cable). There is
  no Postgres, Redis or other service to run.
- Solid Queue for background jobs. In production it runs inside puma
  (`SOLID_QUEUE_IN_PUMA=1`), so the app is a single process.
- Minitest, with fixtures, for the tests. Rubocop in the omakase
  configuration, Brakeman and bundler-audit for checks.
- The converters themselves are Ruby scripts in the repo root that the app
  runs as subprocesses through the `seod` command from the vendored
  se-open-data gem. The app never loads converter code into its own
  process.

## Where things are

```
admin/
  app/controllers/   one controller per resource, plus the Authentication concern
  app/models/        ActiveRecord models and a few plain Ruby settings objects
  app/services/      the pipeline: runs, archives, diffs, unified CSV, datasets
  app/jobs/          Solid Queue jobs, including the minute-by-minute dispatcher
  app/views/         ERB templates; the layout holds the header and flash messages
  app/helpers/       badges, ages, durations and the app version for the views
  app/javascript/    Stimulus controllers (there is one, for the run history)
  app/assets/        the stylesheet (Tailwind input and a hand-written theme)
  lib/mykomap/       the MykoMaps dataset format, ported from the monolith
  lib/open_data.rb   where the converters, downloads and builds live on disk
  lib/tasks/         rake tasks for backfilling row dates and running unification by hand
  engines/data_builder/  the dataset builder wizard, a mountable engine
  mykomaps/          map configs for the one-click dataset build
  db/                migrations, schema, seeds and the YAML files seeds read
  test/              the suite, with helpers, stubs and golden fixtures
```

The converter directories are outside `admin/`, in the repo root.
`OpenData.root` points at them and defaults to `..`, so in development the
app sees the real converters.

## How a page is served

Every controller inherits from `ApplicationController`, which includes the
`Authentication` concern. The concern looks up a `Session` record from a
signed cookie and redirects to the sign-in page when there is none. A
controller action that must work signed out declares it with
`allow_unauthenticated_access`, as `SessionsController` does. The
application controller also sends anyone still on the seeded default
password to the password page and nowhere else.

The current user is in `Current.user`. There is one user table and no
roles: anyone signed in can do everything.

Views are plain ERB. The layout renders the header with the app name, the
version from `CloudronManifest.json`, the three navigation links and the
flash messages, then yields the page. Pages are built from a small set of
CSS classes (`card`, `btn`, `pill`, `tag`, `flash`) defined in
`app/assets/tailwind/application.css`, which starts with the colour
tokens. Tailwind utility classes are available but the pages mostly use
the named classes, so the look stays consistent. Dark mode follows the
browser.

`ApplicationHelper` has the small presentational helpers the pages share:
status badges, the age of the last download coloured by staleness, the
added/removed/changed counts, cron schedules with their time zone and
duration formatting. Put new display logic there rather than in a view.

Buttons that change state are `button_to` forms, so they are POSTs with
CSRF tokens. Turbo handles the form submissions and redirects. The one
piece of JavaScript is a Stimulus controller that hides repeated
"no changes" rows in the run history.

## The models

- `DataSource`: a converter directory. Holds the schedule, the enabled
  flag, the type (auto or manual) and the editable description and
  download URL. `due?` and `overdue?` read the cron expression with the
  fugit gem. `sync_from_repo!` is what seeds call to register new
  directories.
- `DownloadRun`: one run of a source, with status, trigger, log, exit
  code, row counts and the archive path. `reap_stale!` fails runs that
  have been queued or running for six hours, which happens when the app
  restarts mid-job.
- `Project` and `ProjectSource`: projects and their many-to-many link to
  sources. `unify_settings` reads the project's `unify:` section from
  `db/projects.yml` into a `UnifySettings` object.
- `ProjectBuild`: one unified CSV build. `ProjectDataset`: one dataset zip
  built from a build.
- `Secret`: an encrypted key or password. The definitions (name, path,
  description) come from `db/secrets.yml`; only the values are in the
  database. `Secret.env` turns them into the `PASSWORD__*` variables the
  converters read.
- `User` and `Session`: the Rails 8 authentication generator's models.
- `DiskUsage`: hourly measurements for the dashboard card.
- `MapConfig`, `UnifySettings`, `DownloadFilename`: plain Ruby objects
  that read files or build names. They live in `app/models` because that
  is where Rails looks, not because they are tables.

Logs on runs, builds and datasets are text columns appended to with
`append_log`. Keep them that way: the pages show them verbatim and the
tests assert on them.

## Background work

`config/recurring.yml` lists the jobs Solid Queue starts on a timer:

- `ScheduleDispatchJob` every minute. It reaps stale runs, then for each
  enabled source whose cron time has passed since its last run it creates
  a queued `DownloadRun` and enqueues a `DataSourceRunJob`.
- `DiskUsageJob` every hour.
- `DataBuilder::CleanupJob` every day at 03:00.

`DataSourceRunJob` is limited to one job per source at a time with
`limits_concurrency`, because the controllers' "is it running?" checks are
not atomic and two runs of one source must never share its directory.
The other jobs are thin: they hand a record to a service object and
return.

In development `bin/dev` starts puma and the Tailwind watcher. Jobs run
inside puma there too, so a scheduled or manual run works without a
separate worker.

## The pipeline services

`app/services` is where the real work happens. Each class takes a record
in its constructor and has a `call` method.

- `DataSourceRunner`: runs one `DownloadRun`. Installs an uploaded file if
  there is one, runs `bundle install` in the source directory, then
  `seod download` and `seod convert` with a clean environment (the app's
  bundler variables stripped, the secrets added, `SEOD_CONFIG` set to
  `production.conf` when the source has one). Exit code 100 from download
  means no new data. It then stamps the rows, archives, diffs, and
  discards the archive again if the output is byte-identical to the last
  one.
- `RunArchiver`: copies `original-data/`, `standard.csv` and a
  `meta.json` into a dated folder under the downloads root.
- `CsvDiff`: compares two `standard.csv` files on the Identifier column
  and reports added, removed and changed rows, ignoring the date columns.
- `RowStamps`: adds Created At and Updated At to each row by comparing
  with the previous version. `RowStamps::Backfill` reconstructs them from
  the archive history and is run through the `row_stamps:backfill` rake
  task.
- `ProjectBuilder`: a unified CSV build. Cleans each source with
  `UnifiedCsv::Cleaner`, merges with `UnifiedCsv::Unifier`, stamps rows,
  archives and diffs against the previous build.
- `ProjectDatasetBuilder`: a dataset zip from a build, using
  `lib/mykomap` and the project's map config.

`UnifiedCsv` and `lib/mykomap` are ports of TypeScript: the data-pipelines
`clean-csv-data` and `data-unification` packages, and the monolith's
`dataset import` command. They reproduce the original output byte for
byte, including a few things that look like bugs. `db/projects.yml` notes
the ones that matter for the CWM. Do not tidy these without checking the
parity tests described below, and if the behaviour should change, change
it in the TypeScript too or the two pipelines drift apart.

## The dataset builder engine

`engines/data_builder` is a mountable Rails engine at `/data-builder`. It
has its own controllers, models (`Build`, `Template`, `GeocodeEntry`),
services and a `BuildJob`, all namespaced under `DataBuilder`. Its tables
are prefixed `data_builder_`, apart from the geocode cache in
`mykomap_geocode_entries`. Its controllers inherit from the host
app's `ApplicationController`, so sign-in and CSRF apply.

The wizard is one large ERB file holding its own CSS and JavaScript, which
talk to the engine's JSON endpoints with `fetch`. It was ported from the
monolith's admin UI and kept as a single file on purpose, so that it can
be compared with the original. If you change it, check the browser
console: the JavaScript has no build step and no tests of its own. The
engine's Ruby side is tested in `test/data_builder/`.

## Seeds and the YAML files

`db/seeds.rb` runs on every start, in development and in the container.
It creates the default user when there are no users, registers new source
directories (`DataSource.sync_from_repo!`), creates projects and adds
their sources (`Project.sync_from_file!`) and saves secrets found in the
environment (`Secret.seed_from_env!`).

Each sync only fills in blanks. A description, schedule or project name
edited in the UI is never overwritten by a redeploy. If you add a field
that seeds should populate, follow the same rule: set it when the record
is new or the field is blank, and leave it alone otherwise.
[configuration.md](configuration.md) describes the files.

## Database and migrations

The schema is in `db/schema.rb`; the queue, cache and cable schemas have
their own files. `bin/rails db:prepare` creates and migrates everything.

SQLite rebuilds a table when a column is added or removed. Inside the
migration's transaction foreign keys are still enforced, so dropping the
old copy of a parent table cascade-deletes its children. The migration
that introduced `project_sources` shows the workaround: read the rows you
need into memory first, then write them back once the new table exists.
Remember this whenever a migration touches `data_sources` or `projects`.

## Testing

Run everything from `admin/`:

```
mise exec -- bin/rails test
mise exec -- bin/rails test test/services/project_builder_test.rb
mise exec -- bin/rails test test/services/project_builder_test.rb:42
mise exec -- bin/rubocop
mise exec -- bin/ci
```

`bin/ci` runs the same steps as GitHub Actions: rubocop, bundler-audit,
the importmap audit, Brakeman, the tests and a seed replant.

The suite runs in parallel and uses fixtures from `test/fixtures`. Two
helpers do most of the setup:

- `OpenDataTestHelper#setup_open_data_env` points `OPEN_DATA_ROOT`,
  `DOWNLOADS_ROOT` and `BUILDS_ROOT` at a temporary directory and puts
  `test/stub_bin` first on the `PATH`. The stub `seod` there copies a
  `next-download.csv` fixture through the download and convert steps, and
  environment variables make it fail or report no new data. Nothing in the
  suite touches the network or a real converter.
- `SessionTestHelper#sign_in_as` signs a user in by writing the session
  cookie. Controller tests start with it.

`create_source_dir` and `archive_standard_csv` in the open-data helper
build a fixture source and a fake successful run in two lines, so a test
of a build or a diff does not need to run the pipeline first.

Three tests are golden-file comparisons:

- `test/services/unified_csv/data_pipelines_parity_test.rb`: a sample of
  real CWM rows, cleaned and unified by data-pipelines, must come out of
  the Ruby port byte for byte.
- `test/lib/mykomap_dataset_parity_test.rb`: the same sample built into a
  dataset by the monolith's CLI, likewise.
- `test/lib/mykomap_dataset_builder_test.rb` with
  `test/fixtures/files/dataset-cli`: a small synthetic dataset.

When one of these fails after a change to the port, the fix is almost
always in the port. Only regenerate the expected files when the TypeScript
has changed, and say so in the commit message, with the data-pipelines or
monolith commit the new files came from.

`test/lib/deploy_script_test.rb` drives `deploy.sh` with a stub `cloudron`
command, also in `test/stub_bin`, and checks the arguments it is given.

Write the test first. Most classes here were written that way and the
tests double as the specification: when a behaviour looks odd, the test
usually says why it is there.

## Making common changes

**A new field on a source.** Add a migration, add the field to the
`params.expect` list in `DataSourcesController#data_source_params`, add it to
`edit.html.erb` and `show.html.erb`, and decide whether seeds should set
it (see above). Write a controller test that edits it and a model test for
any validation.

**A new page.** Add a route in `config/routes.rb`, a controller action, a
view and a controller test. Use the existing pages as the pattern: a
breadcrumb heading, then cards. Load everything the view needs in the
action so the view has no queries.

**A new recurring job.** Add the job class under `app/jobs`, an entry in
`config/recurring.yml` and a job test. Keep the job thin and put the work
in a service or model method so it can be tested without Solid Queue.

**A new secret.** Add it to `db/secrets.yml` with the `path` the converter's
conf file uses. The Settings page and `Secret.env` pick it up with no code
change. Add a line to the secret model test if the naming is unusual.

**A change to the pipeline.** Reproduce the case in a service test with
the stub seod or a hand-written CSV, make it fail, then change the
service. If the change touches `UnifiedCsv` or `lib/mykomap`, run the
parity tests before and after.

**A change to the look.** The colour tokens are at the top of
`app/assets/tailwind/application.css` and the component classes follow.
`bin/dev` rebuilds the stylesheet as you save. The contrast of each theme
has been checked to WCAG AA; keep it that way if you change a colour.

## Checking a change by hand

Start the app with `bin/dev`, sign in, and use a real converter: pick a
source with a downloader, give it a schedule, press "Download now" and
watch the run page. Downloads land under `admin/storage/downloads` by
default. For a unified CSV build the CWM project needs a successful run
for each of its sources, which takes a while; the `unified_csv:clean` and
`unified_csv:unify` rake tasks run the two steps on CSVs you supply
instead.

On a server, `bin/rails runner` is the quickest way to inspect state or
re-run a step. The run and build pages already show the logs. See
[deployment.md](deployment.md) for how to get a shell in the container.

## Releasing

Bump `version` in `CloudronManifest.json`. The header shows it, so you can
tell at a glance which build a server is running. Then deploy as described
in [deployment.md](deployment.md).
