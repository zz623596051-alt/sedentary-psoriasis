# Sedentary behaviour and psoriasis — analysis code

Analysis code for the manuscript *"Sedentary behaviour, but not physical activity,
is associated with prevalent psoriasis: a cross-sectional and bidirectional Mendelian
randomisation study in US adults."*

## What this repository contains

| Directory | Contents |
|---|---|
| `R/` | The complete analysis pipeline (R 4.5.2) |
| `tools/` | Python helpers: data retrieval, instrument construction, citation verification, submission packaging |
| `output/tables/` | Key result tables (CSV) as reported in the manuscript |
| `docs/` | Methods text, reference list, and the two instrument files used in the Mendelian randomisation |

Raw data are **not** included. Everything is downloaded from public sources at run
time; see "Data sources" below.

## Data sources

All data are public and require no application.

| Source | Contents | Access |
|---|---|---|
| NHANES 2009–2010 / 2011–2012 / 2013–2014 | Demographic, examination, laboratory and questionnaire data | <https://wwwn.cdc.gov/nchs/nhanes/> |
| FinnGen release 12 | `L12_PSORIASIS` (12,760 cases), `L12_PSORI_VULG`, `M13_PSORIARTH` | <https://storage.googleapis.com/finngen-public-data-r12/> |
| GWAS Catalog | `GCST90104339` leisure screen time (n = 526,725) | <https://www.ebi.ac.uk/gwas/> |
| UK Biobank (via MRC-IEU OpenGWAS) | `ukb-b-5192` television viewing (n = 437,887); `ukb-b-4779` computer games | <https://gwas.mrcieu.ac.uk/> |
| 1000 Genomes phase 3 EUR | LD reference panel, accessed via Ensembl REST | <https://rest.ensembl.org/> |

An OpenGWAS API token is required for the UK Biobank outcome step
(`OPENGWAS_JWT` in `.Renviron`; free from <https://api.opengwas.io/>).

## Reproducing the analysis

```r
# 0. Set the R library path and install packages (writes to the isolated library)
source("R/config.R")
Rscript R/00_setup.R

# 1. Download NHANES (30–60 min on first run)
Rscript R/01_download_nhanes.R

# 2. Build the analytic dataset
#    Includes an automatic gate check: MCQ070 case count must be 520
Rscript R/02_build_dataset.R

# 3. Observational analysis (survey-weighted regression, splines, mediation)
Rscript R/03_observational_analysis.R

# 4. Mendelian randomisation, both directions
Rscript R/04b_mr_local.R

# 5. Figures
Rscript R/05_figures_tables.R

# 6. Table 1 statistics
Rscript R/06_table1_stats.R
```

The genetic pipeline has two stages, because instruments were built from local
summary statistics:

```bash
# Forward exposure: GWAS Catalog -> Ensembl alleles + 1000G LD pruning
python tools/extract_iv_from_catalog.py \
  --accessions GCST90104339,GCST006913,GCST90104345 \
  --p-threshold 5e-8 --prune-kb 10000 -o data/raw/iv_from_catalog.tsv
python tools/resolve_alleles_ld.py -i data/raw/iv_from_catalog.tsv \
  -o data/raw/iv_resolved.tsv --r2 0.001

# Outcome data from FinnGen R12 (one pass yields both directions)
python tools/fetch_finngen.py --mode both \
  --endpoints psoriasis,psoriasis_vulg,psoriasis_arth --p-threshold 5e-8

# Reverse exposure: psoriasis instruments
python tools/build_reverse_iv.py --endpoint psoriasis --prune-kb 10000
python tools/resolve_alleles_ld.py -i data/finngen/psoriasis_iv_pruned.tsv \
  -o data/finngen/psoriasis_iv_r2_stage1.tsv --r2 0.001
#   NOTE: resolve_alleles_ld.py does not compute F statistics. With the FinnGen
#   `sebeta` column available, compute F = (beta/se)^2 directly (see Methods 2.5.1).
```

## Validation

The pipeline carries four automated checks, all of which must pass:

| Script | Purpose | Result |
|---|---|---|
| `R/_syntax_check.R` | Parses all R scripts | 12/12 OK |
| `R/_smoke_test.R` | Configuration and formula assertions (base R only) | 50/50 PASS |
| `R/_dryrun_test.R` | Dry run: synthetic NHANES data through the production code path in `R/lib_derive.R` | 33/33 PASS |
| `tools/check_citation_integrity.py` | Every in-text citation resolves to a reference and vice versa | 12/12, exit 0 |

```bash
Rscript R/_syntax_check.R    # -> R/_syntax_report.txt
Rscript R/_smoke_test.R      # -> R/_smoke_report.txt
Rscript R/_dryrun_test.R     # -> R/_dryrun_report.txt
python tools/check_citation_integrity.py \
  --doc docs/10_Discussion初稿.md --refs docs/references_verified.csv
```

The dry run is the substantive one: it exercises `derive_psoriasis_vars()` and
`apply_exclusions()` — the same functions the production build calls — against
synthetic data seeded with sentinel codes, missing values and boundary ages.

## Key results reproduced

| Analysis | Estimate | Source table |
|---|---|---|
| Sedentary time, per 60 min/day | OR 1.065 (95% CI 1.016–1.115), BH-adjusted *P* = 0.026 | `output/tables/model_sedentary_continuous.csv`, `primary_exposures_BH.csv` |
| Physical activity, per 1,000 MET-min/week | OR 0.997 (95% CI 0.981–1.014), *P* = 0.76 | `output/tables/model_PA_continuous.csv` |
| Forward MR (screen time → psoriasis) | IVW OR 0.98 (95% CI 0.80–1.21), *P* = 0.85 | `output/tables/mr_local_summary.csv` |
| Reverse MR (psoriasis → TV viewing) | IVW OR 1.003 (95% CI 0.997–1.009), *P* = 0.28 | `output/tables/mr_local_summary.csv` |

Analytic sample: 15,676 adults, 455 with psoriasis, events-per-variable 32.5.

## Interpretation constraints baked into the code

Two constraints are enforced programmatically rather than left to prose, because
they are the easiest errors to make when reporting null genetic findings:

1. `R/03_observational_analysis.R` asserts that the reported analytic sample size
   equals the number of observations actually available to the fitted model, and
   that the exclusion criteria in `R/lib_derive.R` match the model covariates.
2. `R/08_stats_audit_fixes.R` asserts consistency between the missing-data
   comparison and the analytic sample, and recomputes non-linearity by a
   linear-versus-spline Wald comparison.

## Citation

If you use this code, please cite the manuscript and the data sources listed above.
The reference list is in `docs/15_参考文献表.md` (APA and Vancouver formats); every
entry was verified against both PubMed and Crossref.

## Licence

Code released under the MIT Licence (see `LICENSE`). The underlying data belong to
their respective providers and are subject to those providers' terms of use.
