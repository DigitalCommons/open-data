# Linked Open Data

This document describes the process for generating and publishing Linked Open Data.
Note that this pipeline is no longer the primary purpose of this repository — the
main use case is now generating normalised CSVs for Mykomap. These steps are only
needed if publishing Linked Open Data is required.

## Overview

1. Generate RDF/TTL/HTML files from the standard CSV
2. Deploy files to the web server
3. Populate the triplestore

These steps assume you have already generated a `standard.csv` for your project. 
See [data-standard.md](./data-standard.md) if you haven't done this yet.

## 1. Generate RDF/TTL/HTML

From the project version directory:

```bash
make -f ../../tools/se_open_data/makefiles/generate.mk edition=experimental
```

Generated files are placed in `generated-data/[edition]/www`. You may occasionally 
need to remove this folder before re-running.

## 2. Deploy to server

Requires SSH access — see [setup.md](./setup.md) if you haven't configured this yet.

Run a dry run first to verify the deployment location:

```bash
make -f ../../tools/se_open_data/makefiles/deploy.mk edition=experimental --dry-run
```

If you're happy with the output, deploy for real:

```bash
make -f ../../tools/se_open_data/makefiles/deploy.mk edition=experimental
```

> ⚠️ This will delete live files. Always do a dry run first.

### Known issue: rsync hanging

When deploying a large number of files, the rsync process can hang, possibly due to 
excessive log output. If this happens you may need to run rsync manually with the 
`-v` flag removed. See 
[#174](https://github.com/SolidarityEconomyAssociation/open-data-and-maps/issues/174).

## 3. Populate the triplestore

Requires Virtuoso Conductor access — credentials are on the wiki.

```bash
make -f ../../tools/se_open_data/makefiles/triplestore.mk edition=experimental
```

At the end of this step you will see a message like:
**** IMPORTANT! ****
**** The final step is to load the data into Virtuoso with graph named
**** https://w3id.solidarityeconomy.coop/sea-lod/[graph]/:
**** Execute the following command, providing the password for the Virtuoso dba user:
**** ssh sea-0-admin 'isql-vt localhost dba <password> /home/admin/Virtuoso/BulkLoading/Data/[some_numbers]/loaddata.sql'

Before running the final command:

1. Open [Virtuoso Conductor](http://store1.solidarityeconomy.coop:8890/conductor/sparql_graph.vspx?sid=b1d624245c8092f7b246d8fa1da05743&realm=virtuoso_admin)
2. Navigate to the Graph view and delete the existing graph named in the message above

> ⚠️ Deleting a graph is irreversible. Make sure you're deleting the correct one.

Then run the final command from the message, replacing `<password>` with the 
Virtuoso dba password:

```bash
ssh sea-0-admin 'isql-vt localhost dba <password> /home/admin/Virtuoso/BulkLoading/Data/[some_numbers]/loaddata.sql'
```

Once complete, verify the graph appears in the Virtuoso graph list. If it doesn't, 
run the command again.

### Known issues

- A Conductor error message on upload can usually be ignored. See
  [#172](https://github.com/SolidarityEconomyAssociation/open-data-and-maps/issues/172).
- Do not use browser refresh in Virtuoso Conductor when deleting or uploading graphs —
  this can cause serious problems. See
  [#173](https://github.com/SolidarityEconomyAssociation/open-data-and-maps/issues/173).
