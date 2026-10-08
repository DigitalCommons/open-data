# Using the admin

## Signing in

The first start seeds one user, username `mykomaps`, password `admin`. The
app refuses to go anywhere else until that password is changed. Sign-in is
rate limited to 10 attempts per 3 minutes.

## Dashboard (Projects & Data Sources)

The home page. The summary row shows how many sources there are and in how
many projects, how many are enabled, overdue (a scheduled download missed a
whole cycle) and failing (last run failed), and the disk space used by
downloads and builds.

Below that, one table per project in dashboard order, then "Other sources"
for sources in no project. Each row shows the source, its type (auto or
upload only), schedule, last download and status, an enable switch and a
"Run now" button. A source without a schedule cannot be enabled.

## Source page

Open a source from the dashboard.

- **Download now**: queues a run. Disabled while one is queued or running.
- **Details**: description, projects, download URL, type, cron schedule,
  enabled, last downloaded, last processed, row ID (how the Identifier
  column is made and how stable it is), source directory.
- **Edit**: name, type, schedule, enabled, description and download URL.
  Schedules are cron expressions, optionally followed by a time zone, for
  example `0 6 * * * Europe/London`. The description and download URL are
  seeded from `db/data_source_details.yml` only while blank, so edits made
  here survive redeploys.
- **Manual upload**: for sources without a downloader. Choose the file and
  the app copies it into the source's `original-data/` and converts it.
- **Downloads**: every archived download, newest first, with row count,
  what changed against the previous download, and links to the
  `standard.csv` and the diff. Filenames carry the download date.
- **Run history**: every run with trigger, status, duration and change
  counts. Repeated "no changes" runs are collapsed to the latest one; tick
  the box to show them all. Click a run for its log.

## Project page

Open a project from its dashboard heading.

- **Details**: description, identifier (the key from `db/projects.yml`,
  used in download filenames), category (MykoMaps v4, MykoMaps v3 or
  Legacy) and position (dashboard order). Edit changes name, category,
  position and description.
- **Data sources**: the project's sources with the unification code each
  one has in the unify settings.
- **Unified CSV builds**: "Build unified CSV" queues a build. The table
  lists builds with status, row count, merged row count and changes since
  the previous build. A build page has the log, the archive path and links
  to the unified CSV and the diff.
- **MykoMaps dataset**: "Build dataset" builds a dataset zip from the latest
  successful unified CSV and the map config in `admin/mykomaps/<key>/`.
  Each dataset has a status, row count, log and a zip download. Only
  projects with a map config directory show this section.

## Settings

The Settings link in the header.

- **Change username**: needs the current password.
- **Change password**: at least 8 characters.
- **Secrets**: one field per entry in `db/secrets.yml`, with its status
  (not set, set from the environment, or set and when), where to get it and
  which sources use it. The placeholder shows the last four characters of
  the saved value. Leave a field blank to keep the current value; tick
  Remove to delete it. Saved values are encrypted and override the
  `PASSWORD__*` environment variables.

## Dataset builder

The Dataset builder link in the header opens a wizard that builds a MykoMaps
dataset from any CSV, independently of projects.

1. **Name and data**: upload a CSV, use a project's unified CSV, use a
   source's latest `standard.csv`, import an existing `config.json` or
   start from a saved template. A data preview shows the columns.
2. **Map the CSV columns to properties**
3. **Geocoding**: which columns hold coordinates or addresses
4. **Vocabs**: build controlled vocabularies from CSV columns
5. **Map and interface settings**: initial bounds, logo, property labels
6. **About box**: text per language
7. **Popup layout**

Build produces a dataset zip to download. "Save template" keeps the
configuration for next time. Staged CSVs are deleted after 24 hours.
