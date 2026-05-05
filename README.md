# ECI Assembly Results Archive

This repository packages the constituency-level assembly election results archive I built from ECI and local historical sources.

## Canonical dataset

- `dissemination/eci_assembly_results_since_2009/data/assembly_candidate_results_since_2009.parquet`
- `dissemination/eci_assembly_results_since_2009/data/assembly_candidate_results_since_2009.RData`

The table is one row per candidate per constituency-election result.

## Included source and build files

- `build_eci_assembly_bundle.R`
- `download_eci_assembly_results.R`
- `dissemination/eci_assembly_results_since_2009/scripts/build_eci_assembly_bundle.R`
- `dissemination/eci_assembly_results_since_2009/scripts/download_eci_assembly_results.R`
- `dissemination/eci_assembly_results_since_2009/scripts/eci_assembly_manifest_2021_2026.csv`
- `dissemination/eci_assembly_results_since_2009/README.md`

## Coverage

The archive covers assembly elections from `2009` through `2026` for the election IDs in the manifest. The bundle is complete at both the election level and the constituency level for that manifest.

## Rebuild

```bash
Rscript build_eci_assembly_bundle.R
```

The build script writes the canonical parquet and `.RData` files under `dissemination/eci_assembly_results_since_2009/data/`.

