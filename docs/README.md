# Open Data

This repository contains the scripts used to fetch, normalise and
publish third party datasets of varying quality, such that downstream
users / processes can consume the data in a high-quality form:
specifically [Five Star] grade [Linked Open Data][LOD]. (Also, three and
four star data is generated en-route and published in addition.)

The main use to date is for publishing interactive maps of that data
using the software [MykoMap v4.x][MykoMap] and [MykoMap v3.x].

The normalisation processes herein at the time of writing all use the
conversion framework defined in [se-open-data]. As such they are
mostly intended for data consisting of lists of organisations in the
[Social and Solidarity Economy][SSE]. See the [se-open-data]
documentation for a more in-depth explanation than is warranted here.

> [!NOTE]
> 
> These usages are not intended to be a functional requirement of the
> any of the software above, although they do inform many of the
> assumptions.

> [!NOTE]
>
> This is a Digital Commons Cooperative project. Please follow the
> [contribution guidelines] if you wish to participate.
> 
> For questions or to get involved, please create an issue tagging 
> [@ColmMassey](https://github.com/ColmMassey).

> [!TIP]
> 
> Historically, you may find documents or issues referring to this
> project as the "Sausage Machine" or the "Sausage Factory". We
> generally use the term "data pipeline" for the wider process
> (including the downstream steps), or "SE open data","open data" or
> "normalisation pipeline" for this specific component.

## Inputs and outputs

See the description of input and output data in the [se-open-data]
documentation.

## Consumers of this data

Current processes which consume the data output within Digital Commons
are described below.

### DotCoop, ICA, Workers.coop

These datasets are used to publish maps on the respective membership
organisations' websites. [MykoMap v3.x] maps could use the CSV files
directly, [MykoMap] v4.x requires them to be converted into its own
internal dataset format.

### Cooperative World-Map

Datasets which are lists of co-operative organisations are consumed by
the [data pipelines] project.  That merges them into a single dataset,
via further normalisations and unification of duplicate entries using
various heuristics.

This is then converted into a dataset (or datasets) suitable for
[MykoMap] v4.x.

## Project Structure

For the most part, each subdirectory is dedicated to a specific
upstream dataset.

The directory name is typically an identifier used to represent that
dataset.

Exceptions to this rule are:

- `docs/` - documentation files (such as this).
- `tools/` - tools and scripts.
- `tools/deploy/` - deployment scripts, see [Automated Use](#Automated Use).
- `caches/` - a .gitignored folder, in which temporary files are
  cached (notably geocoding data)
- `.github/` - GitHub specific configuration files.

## Requirements

- Unix/Linux environment. Windows users are advised to use WSL.
- Ruby and Bundler (requirements as for the [se-open-data] Gem)

Optionally:
- [ssh] access to any servers used for deployment
- Passwords for any [Virtuoso] databases used for deployment
- Passwords and API keys required for services used by specific datasets

[ssh] access is typically configured via the [ssh config] in your
account, and will depend on the servers in question. Developers are
assumed to know how to do this, and describing it is out of scope of
this document.

For interactive use, the passwords and API keys are typically assumed
to be stored in an encrypted [Password Store] repository, such that
they can be retrieved using the `pass` command.

For non-interactive use, these secrets are typically assumed to be
available in environment variables.

Both cases are described in more detail in the [se-open-data]
documentation.

## Manual or Automated use?

The normalisation processes can be invoked:

- Manually by the user. *(This is the typical case for datasets which
  cannot be obtained online, needing to be downloaded / extracted and
  potentially inspected before conversion)*
- Automatically by a [cron-job][cron] or [systemd service][systemd]. 
  *(This is the typical case for datasets which can be obtained online
  in a high-quality form which does not need manual oversight to
  process)*

Obviously the latter is preferable in most cases, but the former use
is nevertheless useful for diagnostics and development, even were all
the sources handled by the latter case.

There is a script included which can automate the later case, and a
deployment script to install it as a user-mode service. See
[Deployment](#Deployment).

For a more comprehensive explanation of the conversion process, see
the documentation in the [se-open-data] Gem.

## Manual Usage Synopsis

This is a short overview of the manual process, described more fully
in the documentation for the [se-open-data] gem, but included here as
a quick start reminder.

It is a command-line process assumed to be run in a Linux Bash shell,
and should be executed with the prescribed
[requirements](#Requirements) in place.

Assuming the project is defined by the variable `$PROJECT_NAME`, and
the `password-store` project is checked out in the directory
`$PASSWORD_STORE_WORKING_DIR`, then the steps are:

```bash
# set environment for access to passwords/api keys in the password-store repo
. $PASSWORD_STORE_WORKING_DIR/env-setup

# Remember to update working directory if necessary
git pull

# navigate into the appropriate dataset project directory
cd $PROJECT_NAME

# install the dependencies
bundle install

# Get the original upstream data... This varies from dataset to dataset.
# But if it is automated, you can do this:
bundle exec seod download

# Run the conversion, data generation, and deployment steps in sequence.
bundle exec run_all
```

> [!TIP]
>
> You can split that last step into sub-commands, see the
> [se-open-data] documentation for details.

## Automated Use

For automated use, this repository is typically deployed by `git
clone`-ing it into a dedicated user account, with a user-mode
[systemd] timer invoking the script `tools/deploy/cronjob`. (So named
because previously a system [cron-job][cron] was used).

Before running the `cronjob` itself, typically the git repository is
pulled to get the latest version.

This `cronjob` script requires certain configuration parameters to be
supplied in environment variables. The deployment needs to set up the
service such that these are correct, and schedule the job to be run
periodically.

All of this set-up is automated by a script, `deploy.sh`, described next.

### Deployment

The typical installation process is automated by the script
`deploy.sh`, which you will find in the directory `tools/deploy/`.

> [!NOTE]
> 
> There used to be an Ansible script which performed the preparation
> and setup for installation, but this method supersedes that.

The script itself should be inspected, and includes detailed inline
documentation. 

Essentially you just set your requirements in the environment, and run
the script within the user account dedicated for the purpose. It will
preserve these settings in a file `~/.env`, which should be readable
only by the hosting user account, and perform any other necessary
installations or configuration.

It uses the helper script, `post-pull.rb` to perform much of the
setup. 

This pair of scripts were designed such that:

- `deploy.sh` performs the one-time setup for the initial
  deployment. The administrator runs this once to deploy.
- `post-pull.rb` performs the set-up which is needed whenever the
  repository is updated. It is run by the service, prior to the
  `cronjob` script.

Note, a consequence of this is that the `.env` file created by
`deploy.sh` process is the "source of truth", and modifications to
other scripts or configuration files (e.g. `~/.forward`) will be
overwritten the next time the service runs `post-pull.rb`.

> [!WARNING]
>
> Make sure that `~/.env` remains readable *only to the hosting user
> account* when you modify it.

### Diagnostics

Diagnostics and errors are assumed to be written to standard output /
standard error (as `seod` does). When run as a systemd service, this
will be persisted using the systemd journal.  This means it can be
inspected using `journalctl`.

> [!TIP]
>
> You may also wish to enlarge the default journal size limit,
> otherwise when you inspect the log the parts you are interested in
> it may have been discarded.
>
> Check the systemd documentation for how to do that (which is outside
> the scope of this document).

Errors are also emailed to an email address used for this purpose. It
is set as a parameter given to `deploy.sh`, and therefore persisted in
`~/.env` - change it there if you need to modify it after initial
deployment.

Emails include suspicious lines (those sent to standard error) and the
current service status.This should be enough to determine whether a
deeper investigation is warranted, which can be done by inspecting the
journal logs, and any data files cached in `original-data/` or
`generated-data/` directories within the checked-out `open-data`
working directory.

For example:

```
● se_open_data.service - Rebuilds the datasets in /home/carrot/gitworking
     Loaded: loaded (/home/carrot/.config/systemd/user/se_open_data.service; disabled; vendor preset: enabled)
     Active: deactivating (stop-post) (Result: exit-code) since Mon 2026-05-18 03:13:53 UTC; 9ms ago
TriggeredBy: ● se_open_data.timer
    Process: 3228287 ExecStart=bash -c . "$ASDF_DIR/asdf.sh" && "$SYNC_AND_RUN" (code=exited, status=1/FAILURE)
   Main PID: 3228287 (code=exited, status=1/FAILURE); Control PID: 3231470 (post-sync)
      Tasks: 3 (limit: 9239)
     Memory: 271.4M
        CPU: 2min 35.043s
     CGroup: /user.slice/user-7003.slice/user@7003.service/app.slice/se_open_data.service
             ├─3231470 /bin/bash /home/carrot/post-sync se_open_data.service
             ├─3231471 systemctl --user status se_open_data.service
             └─3231472 mail -s "FAILED (exit-code/exited): se_open_data.service" carrot

May 18 03:13:53 dev-2.digitalcommons.coop bash[3231248]:     !         from /home/carrot/gitworking/caches/gems/se-open-data-7ff5f4af87cd/lib/se_open_data/cli.rb:1289:in `head'
May 18 03:13:53 dev-2.digitalcommons.coop bash[3231248]:     !         from /home/carrot/gitworking/caches/gems/se-open-data-7ff5f4af87cd/lib/se_open_data/cli.rb:1309:in `etag'
May 18 03:13:53 dev-2.digitalcommons.coop bash[3231248]:     !         from /home/carrot/gitworking/caches/gems/se-open-data-7ff5f4af87cd/lib/se_open_data/cli.rb:586:in `http_download'
May 18 03:13:53 dev-2.digitalcommons.coop bash[3231248]:     !         from /home/carrot/gitworking/caches/gems/se-open-data-7ff5f4af87cd/lib/se_open_data/cli.rb:1202:in `method_missing'
May 18 03:13:53 dev-2.digitalcommons.coop bash[3231248]:     !         from /home/carrot/gitworking/workers-coop/downloader:13:in `<main>'
May 18 03:13:53 dev-2.digitalcommons.coop bash[3231248]:     ! E, [2026-05-18T03:13:53.862251 #3231247] ERROR -- /home/carrot/gitworking/caches/gems/se-open-data-7ff5f4af87cd/lib/se_open_data/cli.rb: stopping, download failed
May 18 03:13:53 dev-2.digitalcommons.coop bash[3228549]: FAILED workers-coop (return code 1)
May 18 03:13:53 dev-2.digitalcommons.coop bash[3228549]: FINISHING with 1 failed: workers-coop
May 18 03:13:53 dev-2.digitalcommons.coop bash[3228287]: ABORTING, script failed (return code 0): /home/carrot/gitworking/tools/deploy/cronjob
May 18 03:13:53 dev-2.digitalcommons.coop systemd[1081]: se_open_data.service: Main process exited, code=exited, status=1/FAILURE
```

In the above example, the `workers-coop` dataset failed, or more
specifically, its download script failed.

> [!TIP]
> 
> Lines labelled `FAILED &lt;dataset ID%gt;` are printed in the logs
> for each failure.
>
> The penultimate line labelled `FINISHING` indicates which datasets failed
> to process to completion - the directories (AKA dataset IDs) are listed.
>
> The email subject will have the form `FAILED (&lt;reason&gt;):
> se_open_data.service`. The `&lt;reason&gt;` tag will be
> `success/killed` of the service was interrupted, or
> `exit-code/exited` if it failed of its own accord).
>

> [!TIP]
>
> The `seod` command can be run in the context of the checked-out
> `open-data` repository, but you need to have the environment set up.
>
> Here are some suggested steps to run the conversion process:
> - `ssh` into the server
> - `sudo su - $SEOD_USERNAME` - where `$SEOD_USERNAME` is the user account it
>   was installed within, typically `carrot`
> - `cd $SEOD_WORKING_DIR` - where `$SEOD_WORKING_DIR` is the
>   directory the `open-data` repository is checked out as, typically `gitworking`
> - `cd $DATASET_ID` - where `$DATASET_ID` is the dataset directory you're
>   interested in, e.g. `dotcoop`
> - `bundle install` - if it hasn't been executed already
> - `bundle exec $SHELL` - to get the Ruby environment set up
> - `alias loadenv='while IFS="=" read -r a b; do export "$a"="$b" ;
>   done'` - define this handy alias for loading a .env file - alternatively
>   define it in the user's `~/.bashrc` file
> - `loadenv <~/.env` - load the environment from `~/.env`
> - `seod run_all` - finally! - or alternatively, whichever command you need.

#### Systemd journalling

Assuming the service is called `se_open_data`, the status of the
service can be checked with:

    systemctl --user statust se_open_data

This command can also be used to start and stop the service. Check the
man page for `systemctl` for other useful options.

The journals for this service can be inspected like so:

    journalctl --user -u se_open_data

Check the man page for `journalctl` for useful options. Notably `-f`
to watch the journal, and `-S $TIMESPECIFIER` to limit the amount of
journals shown. `-S "1h ago"` will show the journal entries seen in
the last hour.

> [!TIP]
>
> When searching the journal output, use `grep` to search for:
> - Individual dataset statuses:
>   - `PROCESSING`
>   - `SUCCEEDED`
>   - `NO CHANGES`
>   - `FAILED`
> - Overall dataset statuses:
>   - `FINISHING` - if the script reached the end
>   - `ABORTING` - if the script was interrupted

> [!TIP]
>
> You can adjust the log level by setting the `SEA_LOG_LEVEL` variable
> in `~/.env`, as per the documentation in [se-open-data].

## Development vs Production

Historically, there were two deployments of this project: one for
development data, one for production data. (And yet another would be
the developer's working directory.)

This was to allow for production to be running a "tried and tested
version" of the code whilst also having a "development version" of it.

However, because [Linked Open Data][LOD] uses self-resolving URIs for
entity identifiers, and these resolve in the *global* context of the
internet, if the two deployments shared the same URIs then changes to
the SKOS schemas in *development* would potentially conflict with
those in *production*.

This can probably be dealt with in various ways, but the one in use
was to define two sets of each vocabulary - the production one, and a
development version, which used a host-name prefixed with the `dev.`
subdomain. For instance:

- https://lod.coop/some-vocab/ - the production version of a vocab
- https://dev.lod.coop/some-vocab/ - the development version of a vocab

This would mean that the production deployment of `open-data` would
need to be configured to generate URIs of the first type, and the
development version URIs of the latter.

## Permanent URL redirection

Another point: a common mechanism used for [linked data][LOD] URIs is
to decouple the actual deployment URLs from the standard URIs, by
using what's termed a "Permanent URL", or "PURL" redirection service.

Put simply, the standard URIs need to be stable, but in practice the
hosted location of the resolved data can change. So the standard URIs
are handled by a host which can keep track of where the actual data
is, and redirects queries to the current correct place.

Historically, this was often done using services such as
https://purl.org (now run by the Internet Archive) or https://w3id.org
(hosted by the [W3ID community]).

We used the latter initially, but later started to use our own, which
we registered the domain `lod.coop` for.

This redirection service is managed using the [lod.coop] project.

And in practice, if you add a new `open-data` dataset, you need to
tell the [lod.coop] redirecter project what the ID is and where that
should go, and redeploy it on both `dev.lod.coop` and `lod.coop`.
Details for this are in the project itself.

Without this, the `lod.coop` or `dev.lod.coop` URIs in the data
published will not redirect, and this can make navigation of the HTML
versions difficult, whilst also the resolution of the machine-readable
[RDF] data will fail.



[CSV]: https://en.wikipedia.org/wiki/Comma-separated_values
[Five Star]: https://en.wikipedia.org/wiki/Linked_data#5-star_linked_open_data
[JSON]: https://en.wikipedia.org/wiki/JSON
[LOD]: https://en.wikipedia.org/wiki/Linked_data
[MykoMap v3.x]: https://github.com/DigitalCommons/mykomap
[MykoMap]: https://github.com/DigitalCommons/mykomap-monolith
[Mykomap data repository]: https://github.com/DigitalCommons/cwm-test-data
[Password Store]: https://www.passwordstore.org/
[RDF]: https://en.wikipedia.org/wiki/Resource_Description_Framework
[Ruby Bundler]: https://bundler.io/
[SPARQL]: https://en.wikipedia.org/wiki/SPARQL
[SQL]: https://en.wikipedia.org/wiki/SQL
[SSE]: https://en.wikipedia.org/wiki/Solidarity_economy
[Semantic Web]: https://en.wikipedia.org/wiki/Semantic_Web
[Virtuoso]: https://en.wikipedia.org/wiki/Virtuoso_Universal_Server
[W3ID community]: https://www.w3.org/community/perma-id/
[contribution guidelines]: https://github.com/DigitalCommons#-contributing
[cron]: https://en.wikipedia.org/wiki/Cron
[data pipelines]: https://github.com/DigitalCommons/data-pipelines
[geocoding]: https://en.wikipedia.org/wiki/Address_geocoding
[lod.coop]: https://github.com/digitalCommons/lod.coop
[se-open-data inputs]: https://github.com/DigitalCommons/se-open-data/blob/handover-docs/README.md#input-data
[se-open-data]: github.com/DigitalCommons/se-open-data/
[ssh config]: https://www.ssh.com/academy/ssh/config
[ssh]: https://en.wikipedia.org/wiki/Secure_Shell
[systemd]: https://en.wikipedia.org/wiki/Systemd
[technology-and-infrastructure]: https://github.com/DigitalCommons/technology-and-infrastructure
[triple-store]: https://en.wikipedia.org/wiki/Triplestore

<!-- for emacs
Local Variables:
mode: markdown
eval: (flyspell-mode)
eval: (auto-fill-mode)
End:

 LocalWords:  Triplestore CLI LimeSurvey TTL geolocation queriable JSON Murmurations
 LocalWords:  APIs seod Bundler ESSGLOBAL RDF schemas Gemspec Gemfile api
 LocalWords:  executables geocodable Curado RIPESS MykoMaps URI
 LocalWords:  geolocated Ontologist geocode triplestore geocoder
 LocalWords:  downloader geocontainer CSVs Downloaders ETAG env
 LocalWords:  SeOpenData localisations GeoAPIfy gitignore SEA's
 LocalWords:  bundler's bundler cronjob MykoMap URIs cronjob env
 LocalWords:  gitignored SKOS SPARQL geocoding CSV Geocoding Makefiles 
 LocalWords:  Allemang Hendler Makefile declaratively Javascript
 LocalWords:  geocoded YAML Schemas config LimeSurvey LimeSurveyCore
 LocalWords:  Rebase gemspec DotCoop ICA normalisations subdirectory
 LocalWords:  WSL cron Ansible systemd Systemd journalling LOD MykoMap
 LocalWords:  lod redirecter
 -->
