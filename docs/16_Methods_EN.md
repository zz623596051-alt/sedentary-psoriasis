# 2. Methods（英文投稿版）

> 本文件是投稿正文用的英文 Methods。中文版见 `13_Methods统计与MR段.md`（内部工作稿）。
> 数字全部来自 `output/tables/*.csv`，与中文版逐条一致。

---

## 2.1 Software and versions

All analyses were conducted in R 4.5.2 (Windows x64) using the `survey` package for
complex-survey-weighted estimation, `splines` for restricted cubic splines,
`dplyr`/`tidyr` for data management, `ggplot2` (3.5+) for figures, and `TwoSampleMR`
0.7.11 for Mendelian randomisation. NHANES raw data were retrieved with `nhanesA`
1.4.1 and cached locally as RDS files. Summary statistics for the genetic analyses
were obtained from the FinnGen R12 public release and from the GWAS Catalog.

## 2.2 Study design, weighting and covariates

The analysis used a nationally representative sample of US adults from three
concurrent NHANES cycles: 2009–2010, 2011–2012 and 2013–2014. The analysis window
was determined by data availability for the psoriasis item: **MCQ070** ("Ever been
told you have psoriasis?") was first administered in 2009–2010 and discontinued after
2013–2014, and does not appear in any other cycle examined.

**Complex survey design.** A stratified, clustered design object was constructed with
PSU as the primary sampling unit and SDMVSTRA as the stratum. Two-year weights were
divided by the number of pooled cycles before merging, and strata containing a single
PSU were handled with `survey.lonely.psu = "adjust"`. All estimates, variances and
*P* values were computed under this design using `svyglm`, `svymean` and `svychisq`.

**Covariate set (ten covariates in the primary model):** age, sex, race/ethnicity
(five categories), education (five categories), family income-to-poverty ratio,
smoking status (never/former/current), daily alcohol intake in grams, diabetes and
hypertension. Body mass index and C-reactive protein were **not** included in the
primary models because they are the mediators under examination (Section 2.4).

**Total cholesterol** was reported in Table 1 but excluded from the models: it was
missing for 9.4% of participants and is not a plausible confounder of the
exposure–outcome relationship. After its exclusion the events-per-variable ratio for
the primary model was 32.5.

**Sample-size consistency.** The reported analytic sample (n = 15,676) is the number
actually analysed. The exclusion criteria and the covariate list are enforced to be
identical in code, with an automated assertion that the reported and analysed sample
sizes agree. Among complete cases there were 455 participants with psoriasis
(prevalence 2.90%).

## 2.3 Exposures, outcome and multiple-testing control

**Two primary exposures were prespecified in the analysis plan:** physical activity
(per 1,000 MET-min/week) and sedentary time (per 60 min/day). **The family of tests
for multiple-testing control was defined a priori as the two continuous primary
exposures (n = 2)**, with false discovery rate controlled by the Benjamini–Hochberg
procedure. This prespecification is what allows the primary result to be interpreted as
designed rather than as one of several exploratory tests: had all nine exposure tests
reported in the paper been treated as a single family, the sedentary association would
not have survived correction (*P* = 0.098).

**Secondary exposures** (physical activity by category, sedentary time by quartile,
and accelerometer-measured activity volume) were **not** included in the correction
family and their *P* values are reported as exploratory.

**Outcome.** Prevalent psoriasis was defined by a self-reported physician diagnosis
(MCQ070 = 1). Severity category (MCQ075) and psoriatic arthritis (MCQ195 = 3) were
used only in exploratory sensitivity analyses.

## 2.4 Dose–response, sensitivity and mediation

**Restricted cubic splines** were fitted with 3 degrees of freedom, with physical
activity log1p-transformed and both exposures referenced to the median.
**Departure from linearity was assessed by a Wald comparison of the linear and spline
models** (physical activity *P* = 0.62; sedentary time *P* = 0.21), rather than by an
overall test of the spline terms, which addresses a different question (whether the
exposure is associated with the outcome at all, not whether the relationship departs
from linearity).

**Sensitivity analyses** examined accelerometer-measured activity and three more
specific psoriasis phenotypes (moderate-to-severe disease, medication-confirmed
disease, psoriatic arthritis). **These must be interpreted with explicit reference to
power**: the case counts were 62, 38 and 35 respectively, giving events-per-variable
ratios of 4.1, 2.5 and 2.3, all well below the requirement of 10. They are therefore
exploratory prompts and **lack the power to detect an association**; they should not be
described as confirming robustness.

**Missing data** were handled by complete-case analysis for the primary covariates. The
main source of missingness was the income-to-poverty ratio (8.95% of participants with
psoriasis status available). **Participants excluded for incomplete covariates did not
differ from those included in psoriasis prevalence** (2.70% versus 2.90%, χ² *P* =
0.70), although excluded participants were slightly older (51.7 versus 49.2 years) and
less physically active (2,796 versus 2,977 MET-min/week). In a sensitivity analysis the
income-to-poverty ratio was dropped to recover participants with missing income data
(n = 17,201); the primary estimate was essentially unchanged (sedentary time OR 1.059,
95% CI 1.011–1.109; physical activity OR 0.996, 95% CI 0.980–1.011).

**Mediation analysis (exploratory; no inference drawn).** Adiposity (BMI) and
C-reactive protein (CRP) were examined as mediators using a bootstrap procedure that
resampled primary sampling units within strata (500 replicates). Because the total
effect of physical activity was close to the null, **the proportion mediated is not
mathematically interpretable**, and the two estimation approaches disagreed in sign;
proportions mediated are therefore not reported as findings. CRP was missing for
67.4% of participants, so that mediation model contained 32% of the analytic sample.
**This analysis is exploratory and supports no inference.**

## 2.5 Bidirectional two-sample Mendelian randomisation

### 2.5.1 Instrument construction

Because the OpenGWAS endpoint for programmatic instrument construction was unavailable
during the study period, **both exposure and outcome data were obtained from public
summary statistics**.

| Role | Source |
|---|---|
| Forward exposure | GWAS Catalog `GCST90104339`, "Leisure screen time", n = 526,725 |
| Reverse exposure | FinnGen R12 `L12_PSORIASIS`, 12,760 cases |
| Forward outcomes | FinnGen R12 `L12_PSORIASIS` (12,760 cases), `L12_PSORI_VULG` (7,912 cases), `M13_PSORIARTH` (4,290 cases) |
| Reverse outcomes | UK Biobank `ukb-b-5192`, "Time spent watching television (TV)", n = 437,887; `ukb-b-4779`, "Plays computer games", n = 462,433 |

**Screening (forward exposure).** A search of the GWAS Catalog association table at
*P* < 5 × 10⁻⁸ yielded 91 candidate variants; 26 independent instruments remained
after excluding variants lacking effect-allele information.

**Screening (reverse exposure).** Variants with *P* < 5 × 10⁻⁸ in the FinnGen R12
summary statistics numbered 22,648 (after expanding multi-rsID records). Distance
pruning in ascending order of *P* (10 kb) reduced this to 35, and allele resolution
plus LD pruning left **15 independent instruments**.

**LD reference panel:** 1000 Genomes phase 3 EUR, accessed through the Ensembl REST
endpoint `/ld/human/{rsid}/1000GENOMES:phase_3:EUR`, at an r² threshold of 0.001.
**Allele resolution:** Ensembl `/variation/human/{rsid}`, traversing all assembly
mappings and selecting the one matching the reported chromosome and position with the
fewest alleles. Palindromic variants were retained only when the effect-allele
frequency lay between 0.42 and 0.58; multi-nucleotide (indel) variants were excluded
conservatively.

**Instrument strength:** all instruments had F statistics above 10 — F = 28.3–73.5 for
the forward exposure and F = 31.0–1373.6 for the reverse exposure. **Methodological
note:** the exposure GWAS come from UK Biobank (United Kingdom) and the outcome GWAS
from FinnGen (Finland), so the two populations do not overlap and sample-overlap bias
is absent.

### 2.5.2 Analyses

**The primary estimator was inverse variance weighting (IVW)**, with weighted median,
MR-Egger, simple mode and weighted mode reported as robustness analyses. **Subtype
analyses** (psoriasis vulgaris, psoriatic arthritis) and the **reverse direction**
(psoriasis → sedentary behaviour) were run through the identical pipeline.

**Heterogeneity and pleiotropy** were assessed by Cochran's Q and by the MR-Egger
intercept test respectively. **Leave-one-out** analysis recalculated the estimate with
each variant omitted in turn to identify any that drove the result, and **single-SNP
analysis** reported the individual estimate for every instrument.

**Analyses not performed, and why.**
*Multivariate Mendelian randomisation* was not performed: physical activity and
sedentary behaviour are highly correlated at the genetic level, while the physical
activity instruments in the available summary statistics did not meet completeness
requirements (several studies provided neither effect alleles nor frequencies), so a
usable physical activity instrument set could not be constructed. The independent
effect of sedentary behaviour is therefore not conditionally adjusted.
*Mediation Mendelian randomisation* (exposure → CRP/BMI → psoriasis) was not performed
because the mediator instruments depend on the same unavailable endpoint.
*The Steiger directionality test* was not implemented; this is a substantive
limitation (Section 2.5.4).

**Proxy variants.** Two of the 15 reverse-direction instruments had no direct outcome
measurement and were replaced by proxies identified by OpenGWAS at r² > 0.8 (13 of 15
matched directly).

### 2.5.3 Prespecified rules for interpreting null results

To avoid selective reporting of null findings, the following rules were specified in
advance.
- If the forward 95% confidence interval **contains** the observational point
estimate, the result is to be reported as **"not supported"** and **not** as
  refutation or contradiction.
- If the reverse direction is non-significant, the result is to be reported as
  **"no reverse effect detected"**, with the effect size corresponding to the upper
  confidence limit stated explicitly, and **not** as "evidence of no effect".

### 2.5.4 Limitations specific to the genetic analysis

1. **Screen time is a proxy for self-reported sitting time**; the two constructs
   overlap only partially, and this is a plausible contributor to the null result.
2. **The Steiger directionality test was not implemented**, so tool-variable
   directionality cannot be fully excluded on genetic grounds.
3. **Multivariate MR was not performed**, so the independent effect of sedentary
   behaviour is not conditionally adjusted.
4. **The reverse analysis is not powered to exclude small effects**: the upper
   confidence limit for television viewing time corresponds to approximately 0.9% per
   unit.
5. **Instruments were derived and pruned by this study** rather than taken from an
   established pipeline. The analysis is fully reproducible from public files, but
   equivalence with the field's standard pipeline was not independently validated.

---

## S4. STROBE-MR checklist

| Item | Status | Note |
|---|---|---|
| **Title and abstract** | | |
| 1 Indicates a Mendelian randomisation study | ✅ | Title states "bidirectional two-sample Mendelian randomisation" |
| 2 Summarises bias risk and limitations | ✅ | See Discussion Section 4.6 |
| **Introduction** | | |
| 3 Background and rationale | ✅ | Section 4.2 |
| 4 States objectives and prespecified hypotheses | ✅ | Opening of Section 4.5; bidirectional causal hypothesis |
| **Methods** | | |
| 5 Reports data sources and eligibility | ✅ | Table in Section 2.5.1 |
| 6 Instrument selection criteria and thresholds | ✅ | *P* < 5 × 10⁻⁸, 10 kb, r² 0.001 |
| 7 LD reference panel information | ✅ | 1000 Genomes phase 3 EUR (Ensembl) |
| 8 Instrument strength (F statistics) | ✅ | Forward 28.3–73.5; reverse 31.0–1373.6; all > 10 |
| 9 Effect alleles and strand handling | ✅ | Section 2.5.1; palindromic EAF restriction; indel exclusion |
| 10 Statistical model and primary estimator | ✅ | IVW primary; four robustness estimators reported |
| 11 Heterogeneity and pleiotropy tests | ✅ | Cochran's Q; MR-Egger intercept |
| 12 Sensitivity analyses | ✅ | Leave-one-out, single-SNP, subtype analyses |
| 13 Software and versions | ✅ | Section 2.1 |
| 14 Use and declaration of proxy variants | ✅ | End of Section 2.5.2 (2 variants, r² > 0.8) |
| 15 Analyses not performed and why | ✅ | Section 2.5.2 (MVMR, mediation MR, Steiger) |
| 16 Prespecified rules for result interpretation | ✅ | Section 2.5.3 |
| **Results** | | |
| 17 Instrument count and F statistics | ✅ | Results Section 3.9.1 |
| 18 Primary and robustness estimates | ✅ | Results Sections 3.9.2, 3.9.3 |
| 19 Heterogeneity and pleiotropy | ✅ | Q and Egger intercept *P* values per outcome |
| 20 Correct reporting of null results | ✅ | Section 3.9.4 ("not supported", not "refuted") |
| **Discussion** | | |
| 21 Consistency with observational evidence | ✅ | Section 4.5, paragraph 2 (CI contains point estimate) |
| 22 Limitations and effect-size bounds | ✅ | Sections 4.5 and 2.5.4 |
| 23 Declaration of construct mismatch | ✅ | Section 4.5 closing; Section 2.5.4 item 1 |
| **Other** | | |
| 24 Statement of reporting guideline | ✅ | This checklist |
| 25 Data and code availability | ⚠️ | **To do**: repository URL / Zenodo DOI to be added |
| 26 Funding and conflicts of interest | ⚠️ | **To do**: to be completed at submission |
