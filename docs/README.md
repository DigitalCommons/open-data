# Open Data

This repository contains the scripts and data used to fetch and normalise CSV data 
for use with [Mykomap](https://github.com/DigitalCommons/mykomap-monolith). The 
normalised CSVs are optionally merged and deduplicated using [data pipelines](https://github.com/DigitalCommons/data-pipelines) and then converted into Mykomap datasets using the dataset script 
in the Mykomap repository, and stored in the 
[Mykomap data repository](https://github.com/DigitalCommons/cwm-test-data).

This is a Digital Commons Cooperative project. Please follow the 
[contribution guidelines](https://github.com/DigitalCommons#-contributing) if you 
wish to participate.

## Requirements

- Unix/Linux environment (macOS or Ubuntu recommended). Windows users should use WSL.
- Ruby and required gems — see [docs/setup.md](./docs/setup.md)
- GNU Make
- SSH access to the server (for deployment)
- A Geoapify API key and source CSV data — request from the repository manager

## Usage

Navigate into the project folder you're working on:

```bash
cd [project_name]/[project_version]/
```

### 1. Convert to standard format

```bash
make -f csv.mk edition=experimental
```

See [docs/data-standard.md](./docs/data-standard.md) for details on the standard 
format and how to write a `converter.rb` script for a new project.

### 2. Generate RDF/TTL/HTML (optional)

This step is only needed if publishing Linked Open Data. See 
[docs/linked-open-data.md](./docs/linked-open-data.md) for full instructions 
including deployment and triplestore population.

## Management

For questions or to get involved, please create an issue tagging 
[@ColmMassey](https://github.com/ColmMassey).
