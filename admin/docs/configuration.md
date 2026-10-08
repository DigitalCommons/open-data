# Configuration

Sources, projects, secrets and map configs are defined in files in the
repo. `db:seed` runs on every start and syncs them into the database:
new entries are created and listed sources are added to projects, but
names, descriptions, schedules and anything else edited in the UI are
never overwritten.

## db/projects.yml

One entry per project, in dashboard order:

```yaml
powys:
  name: Powys Food Map
  category: mykomaps_v4        # mykomaps_v4, mykomaps_v3 or legacy
  position: 20                 # optional; defaults to 10, 20, 30 in file order
  description: >-
    Shown on the project page.
  sources: [ powys-eng, powys-cym ]
```

A `unify:` section turns on unified CSV builds. It mirrors the
data-pipelines `defs.ts` for the project:

```yaml
  unify:
    match_on: [ Domains, CUK ID ]          # columns rows are matched on
    field_priorities:
      default: [ ica, cuk, dc, ncba ]      # which table wins each field
      name: [ ica, dc, cuk, ncba ]         # per-field override
    tables:
      cuk: { source: coops-uk, match: { Domains: Domains, CUK ID: Identifier } }
      dc:  { source: dotcoop, match: { Domains: Domains }, include_cols: [ Domains ] }
      fca: { source: fca }                 # no match: rows are never merged
```

`tables` keys are the unification codes shown on the project page. `match`
maps a `match_on` column to the column holding it in that source.

## db/data_source_details.yml

Per source directory: `description` and `download_url`, applied when the
database values are blank, and `row_id`, a read-only note on how the
Identifier column is made and how stable it is.

```yaml
nfca:
  description: >-
    Where the data comes from and what the converter does to it.
  download_url: https://example.org/export.csv
  row_id: >-
    Which column becomes the Identifier and whether it is stable.
```

## db/secrets.yml

The keys and passwords converters read through se-open-data's
PasswordStore. `path` is the value of a `*_PATH` setting in a source's conf
file. The converter receives it as `PASSWORD__<PATH>` with the path
upper-cased and every other character replaced by `_`, so
`services/mapbox/landexplorer.txt` becomes
`PASSWORD__SERVICES_MAPBOX_LANDEXPLORER_TXT`.

```yaml
mapbox:
  path: services/mapbox/landexplorer.txt
  name: Mapbox access token
  description: Geocodes addresses for Co-ops UK, NFCA and the Powys Food Map.
  where: Mapbox account https://account.mapbox.com/access-tokens
```

Values come from the Settings page or from the environment: a
`PASSWORD__*` variable set on the app is saved on first start where nothing
is saved yet. Saved values are encrypted with keys derived from
`SECRET_KEY_BASE`.

## mykomaps/

Map configs for the one-click dataset build on the project page.
`base.json` is shared and `<project-key>/config.json` is merged over it,
with `about.md` and `assets/` copied into the dataset. A project with no
directory here has no dataset section.

## Adding a source

1. Create the converter directory in the repo root, as for any open-data
   source: `converter`, `downloader` for automatic sources, `schema.yml`,
   `output.yml`, `default.conf` and `production.conf`, and a `Gemfile`.
   Conf settings that are paths to secrets must appear in `db/secrets.yml`.
2. Add its description, download URL and row ID note to
   `db/data_source_details.yml`.
3. Add it to the `sources` list of a project in `db/projects.yml`, and to
   the project's `unify.tables` if the project builds a unified CSV.
4. Deploy. The source appears on the dashboard disabled and without a
   schedule. Give it a schedule on its edit page and enable it, or upload a
   file if it is a manual source.

## Adding a project

Add an entry to `db/projects.yml` and deploy. For a dataset build, add
`mykomaps/<key>/config.json`, `about.md` and `assets/`.
