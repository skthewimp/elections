# Workspace Guide

This repository now has a split between the active assembly archive workflow and the older historical workspace it depends on.

## Top-level layout

- `assembly/`: publishable bundle with the canonical `parquet` and `.RData` release files
- `scripts/assembly/`: active assembly build and download scripts plus the manifest
- `scripts/analysis/`: current analysis notebooks tied to the cleaned assembly bundle
- `scripts/tools/`: small utility scripts
- `docs/notes/`: markdown notes and draft writing connected to current work
- `data/assembly/raw/`: raw scraped inputs used by the assembly workflow
- `geo/`: maps and other geospatial reference assets
- `external/`: vendored repositories and third-party source folders kept intact
- `releases/`: packaged dissemination output kept separate from the main bundle
- `legacy/`: organized historical archive
- `legacy/_flat_compat/`: hidden compatibility layer that preserves the old flat-file layout for older scripts

## Where specific things went

- Old loose root files were reorganized into the typed folders under `legacy/`.
- The former root `eci_assembly_results/` moved to `data/assembly/raw/eci_assembly_results/`.
- The former root `indiatoday_assembly_results/` moved to `data/assembly/raw/indiatoday_assembly_results/`.
- The former root `maps/`, `AC_Data/`, `PC_Data/`, `ALL_PC_Form20/`, and `constituencies/` moved under `geo/`.
- The former root `sources/`, `Delhi-Election-Data/`, and `votestoseats/` moved under `external/`.
- The former root `dissemination/` moved under `releases/`.

## Legacy archive layout

- `legacy/analyses/notebooks/`: old R Markdown notebooks
- `legacy/analyses/rendered/`: rendered notebook HTML and other saved analysis pages
- `legacy/scripts/r/`: standalone historical R scripts
- `legacy/scripts/python/`: standalone historical Python scripts
- `legacy/data/rdata/`: `.RData` and similar binary R work files
- `legacy/data/tabular_csv/`: legacy CSV datasets
- `legacy/data/spreadsheets/`: Excel workbooks
- `legacy/data/text/`: text/reference files
- `legacy/data/archives/`: archive/tar-style inputs
- `legacy/docs/reports/`: PDFs, Word docs, and report-style outputs
- `legacy/media/raster/`: PNG and similar raster images
- `legacy/media/vector/`: SVG/PS vector outputs
- `legacy/spatial/shapefiles/`: local shapefile components and related geometry artifacts
- `legacy/spatial/other/`: spatial-adjacent extras such as SQL dumps
- `legacy/apps/`: preserved app/workspace subprojects such as `figure`, `hebbal`, `parliament`, and `rounds`

## Compatibility notes

- `legacy/_flat_compat/` contains symlinks back to the organized `legacy/` archive plus the shared moved directories such as `maps/`, `sources/`, and `eci_assembly_results/`.
- The active assembly scripts no longer assume they are run from the repo root. They locate the repo automatically and write to the new `scripts/`, `data/`, and `geo/` paths.
- `scripts/assembly/build_eci_assembly_bundle.R` still reads historical source files from `legacy/_flat_compat/`, because the older source import code expects a flat workspace with original filenames.

## Common entry points

- Rebuild the archive: `Rscript scripts/assembly/build_eci_assembly_bundle.R`
- Refresh live ECI scrape files: `Rscript scripts/assembly/download_eci_assembly_results.R`
- Open the publishable dataset docs: `assembly/README.md`
