# ECI Assembly Results Archive

This repository packages a cleaned, publication-ready archive of Indian state assembly constituency results from `2009` through `2026`.

The release is intentionally simple:

- `assembly/` is the distributable bundle
- `build_eci_assembly_bundle.R` rebuilds the bundle from the workspace sources
- `download_eci_assembly_results.R` is the one-off ECI fetch helper

## What is inside

The canonical outputs live in:

- `assembly/data/assembly_candidate_results_since_2009.parquet`
- `assembly/data/assembly_candidate_results_since_2009.RData`

The current build has `161,760` candidate rows across `119` election IDs.

The bundle also includes the release docs and scripts under:

- `assembly/README.md`
- `assembly/scripts/`

## Dataset contract

The table is one row per candidate in one assembly constituency election result.

Key columns:

- `election_id`, `election_year`, `election_month`, `election_month_label`
- `state_name`, `constituency_no`, `constituency_name`
- `candidate`, `party`
- `evm_votes`, `postal_votes`, `total_votes`, `vote_pct`
- `position`, `winner`
- `source_kind`, `source_dataset`, `source_file`, `source_url`, `fetch_method`

That means the parquet is analysis-ready without any reshaping for the usual seat-share, vote-share, or incumbent-style work.

## Source provenance

The archive combines several source families:

- historical ECI candidate tables for `2009-2017`
- local state-election result files for `2018-2020`
- local TCPD candidate data for `2021-2023`
- official ECI statistical reports for the missing `2024-2025` cycles
- live ECI scrapes for `2026`

The `source_kind` field records which source family each row came from, so downstream users can filter or audit the provenance if they need to.

Some elections needed special handling:

- the 2019 Andhra Pradesh, Arunachal Pradesh, Odisha, and Sikkim elections were recovered from `latestAssemblyElectionsIndia.RData`
- unopposed Arunachal Pradesh 2024 constituencies were added from the official constituency reports
- a few 2023 and 2024-2025 gaps were filled from official ECI archive/statistical-report sources

## Coverage

The current bundle matches the manifest and is complete at both the election level and constituency level for the manifest-covered election IDs.

## Rebuild

```bash
Rscript build_eci_assembly_bundle.R
```

The build script writes the bundle to `assembly/` and copies the release scripts into that same folder.

## Using the data

In R, read the `.RData` if you want the exact object used for publication, or read the parquet if you want the cleanest interchange format.

```r
load("assembly/data/assembly_candidate_results_since_2009.RData")
# or
arrow::read_parquet("assembly/data/assembly_candidate_results_since_2009.parquet")
```

## Notes

- `parquet` is the primary exchange format
- `.RData` is kept for compatibility with existing R workflows
- the workspace contains many older scratch files, but only the release bundle and the two build scripts are intended for distribution
