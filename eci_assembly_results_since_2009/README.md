# Assembly Candidate Results Since 2009

This folder is the publishable archive for the state assembly candidate-level results available in this workspace.

It is the only folder intended for distribution. The parent repository also keeps the root-level build scripts used to regenerate it.

It contains one canonical dataset:

- `data/assembly_candidate_results_since_2009.parquet`

And one R-native copy of the same table:

- `data/assembly_candidate_results_since_2009.RData`

The release also includes the build and download scripts under `scripts/`.

As currently built, the bundle contains `161,760` candidate rows across `119` election IDs.

## Data shape

The dataset is one row per candidate per assembly constituency election result.

Main columns:

- `election_id`
- `election_year`
- `election_month`
- `election_month_label`
- `state_name`
- `constituency_no`
- `constituency_name`
- `candidate`
- `party`
- `evm_votes`
- `postal_votes`
- `total_votes`
- `vote_pct`
- `position`
- `winner`
- `source_kind`
- `source_dataset`
- `source_file`
- `source_url`
- `fetch_method`

The row granularity matters:

- one constituency-election can have many candidate rows
- the winning candidate is flagged with `winner = TRUE`
- `position` is the rank within the constituency result, with ties handled conservatively
- `vote_pct` is present when the source provided it or when it can be computed from the constituency totals

## Source mix

The bundle merges:

- local historical ECI candidate data for `2009-2017`
- local state-level result files for `2018-2020`
- local TCPD candidate data for `2021-2023`
- successful ECI live scrapes for `2026`

The `source_kind` column is the audit trail. It lets you separate historical local data, TCPD imports, official ECI report extracts, live scrapes, and the small one-off gap fixes that were needed to complete the archive.

The `2019` Andhra Pradesh, Arunachal Pradesh, Odisha, and Sikkim assembly elections are filled from `latestAssemblyElectionsIndia.RData`, because those state results were not otherwise present in a cleaner local file.

## Coverage check

The archive is now complete for the manifest-covered election IDs and constituency counts. Earlier gaps in `2023-2025` were patched from official ECI statistical reports and archive rows.

## Layout

```text
eci_assembly_results_since_2009/
  README.md
  data/
    assembly_candidate_results_since_2009.parquet
    assembly_candidate_results_since_2009.RData
  scripts/
    build_eci_assembly_bundle.R
    download_eci_assembly_results.R
    eci_assembly_manifest_2021_2026.csv
```

## Scripts

- `scripts/download_eci_assembly_results.R`
- `scripts/build_eci_assembly_bundle.R`
- `scripts/eci_assembly_manifest_2021_2026.csv`
