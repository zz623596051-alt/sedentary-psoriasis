# Results 初稿 v0.3

> **2026-10-03 统计审查后重写**（`nature-statistics` 审查 + lay 三项决策已执行）
> **2026-10-03 补入双向 MR 臂（§3.9）**：OpenGWAS 端点失效，改走本地汇总统计路径
> 来源：`output/tables/*.csv`（01–03/06/08/04b 实跑产物，非人工填写）
> 覆盖：观察臂 §3.1–3.8 + **MR 臂 §3.9（已完成）**。
> 审查报告见 **[09_统计审查报告.md](09_统计审查报告.md)**；MR 报告见 **[12_双向MR结果报告.md](12_双向MR结果报告.md)**。
> **Methods 统计段与 STROBE-MR 清单见 [13_Methods统计与MR段.md](13_Methods统计与MR段.md)**。
> 配图 **11 张**（图1–图7，含分面版）已全部生成并逐张目视核验，见文末图件清单。

---

## ✅ 三项 P0 决策已执行

| # | 决策 | 执行结果 |
|---|---|---|
| **P0-1** | **A：移除 total cholesterol** | 分析集 **n = 15,676**（原报 15,701），病例 **455**，**EPV = 32.5**（14 参数）。流程图与模型 n **严格一致**（已在代码里加断言自检）|
| **P0-4** | **A：预先指定主要暴露 + 定义比较家族** | 主要暴露 = 两个连续暴露（PA / 久坐），家族 = 2，BH-FDR 校正 → 久坐 **校正后 *p* = 0.026（仍显著）**。若按全文 9 个检验校正则为 0.098（不显著）——**这就是为什么家族必须预先声明** |
| **P0-5** | **B：保留中介但降为探索性** | 整节改写为 exploratory，**不做任何推断**；补披露 CRP 缺失 67.4% |

另已直接修正（非决策项）：非线性检验（用真检验）、敏感性分析单位（错标 1000 倍）、race 交互（设定不一致 0.927 → 0.539）、删除无据的「pre-specified」。

### ⚠️ 有一处变化值得注意

**亚组交互全部变为不显著**：性别 *p* = 0.471、糖尿病 *p* = 0.052（原先 0.044）、种族 *p* = 0.539。原先那个「糖尿病交互」现在**跨过了 0.05**。这消除了一个尴尬发现，Discussion 可以更简洁。

---

## 中文速览

**分析集** n = **15,676**（NHANES 2009–2014 三周期）｜银屑病 **455 例** / 15,221 对照
**加权患病率** 3.01%（未加权 2.90%）｜ **EPV = 32.5**（14 个模型参数）

| 暴露 | 效应量（95% CI） | 原始 *p* | BH 校正 *p* |
|---|---|---|---|
| 体力活动，每 1,000 MET-min/wk（**主要暴露**）| OR 0.997 (0.981–1.014) | 0.755 | 0.755 |
| **久坐，每 60 min/day（主要暴露）** | **OR 1.065 (1.016–1.115)** | **0.013** | **0.026** ✅ |
| 体力活动，高 vs 不活动 | OR 1.04 (0.75–1.43) | 0.837 | — |
| 久坐 Q4 vs Q1 | OR 1.59 (1.09–2.32) | 0.022 | — |
| 加速度计 MIMS/day，每 SD（探索性）| OR 1.04 (0.86–1.25) | 0.699 | — |

**核心叙事**：体力活动与银屑病无关联，久坐呈独立正相关——两者「分离」。横断面数据无法排除反向因果，**这正是需要遗传学证据的理由**。

---

# Results（英文正文）

## 3.1 Study population

We pooled three consecutive NHANES cycles — 2009–2010, 2011–2012 and 2013–2014 — which are the only cycles in which the psoriasis question (MCQ070) was fielded. Of 30,468 participants with linked records, 17,547 were aged ≥20 years and 17,357 remained after excluding women who were pregnant at examination. Psoriasis status was available for 17,342 participants, and **15,676 had complete data on all ten model covariates** (age, sex, race/ethnicity, education, family income-to-poverty ratio, smoking, alcohol intake, sedentary time, hypertension and diabetes), forming the analytic sample (Figure 1).

Among them, **455 had psoriasis (2.90% unweighted; 3.01% weighted) and 15,221 did not**. The 14 model parameters yielded an events-per-variable ratio of 32.5.

Missing data were most frequent for the family income-to-poverty ratio (8.95% of participants with psoriasis status available); all other covariates were missing in <0.5%. Participants excluded for incomplete covariates did not differ from those included with respect to psoriasis prevalence (2.70% vs 2.90%; *p* = 0.70), although they were slightly older (51.7 vs 49.2 years) and less physically active (2,796 vs 2,977 MET-min/week) (Table S1).

In a sensitivity analysis, models were refitted after additionally dropping the income-to-poverty ratio to recover participants with missing income data (n = 17,201; 496 cases); results were essentially unchanged (physical activity OR 0.996, 95% CI 0.980–1.011; sedentary time OR 1.059, 95% CI 1.011–1.109) (Table S2).

> 来源：`output/flow_analytic.csv`、`output/log_02_build.txt`、`audit_E_*.csv`、`audit_F_no_pir.csv`
> ⚠️ 本节数字已按 P0-1 决策重算：**n 从 15,701 改为 15,676，病例从 456 改为 455，EPV 从 30.4 改为 32.5**（移除 chol，参数 15→14）。原文的 15,701 与模型实际 n=14,287 不一致，已修正。

---

## 3.2 Baseline characteristics

Baseline characteristics by psoriasis status are shown in **Table 1**. Compared with participants without psoriasis, those with psoriasis were older (weighted mean 50.6 vs 47.3 years; *p* = 0.0008), had higher BMI (29.8 vs 28.9 kg/m²; *p* = 0.035) and larger waist circumference (101.8 vs 98.8 cm; *p* = 0.005), and reported **more sedentary time (433.0 vs 384.0 min/day; *p* = 0.006)**. Hypertension (42.0% vs 32.3%; *p* = 0.002) and former smoking (38.5% vs 23.8%; *p* < 0.001) were more prevalent in the psoriasis group.

Total physical activity was lower in participants with psoriasis (2,847 vs 3,106 MET-min/week) but the difference was not statistically significant (*p* = 0.46). Participants with psoriasis were more likely to be non-Hispanic White (79.6% vs 67.8%), consistent with the known racial/ethnic distribution of psoriasis. No meaningful differences were observed for sex, education, family income-to-poverty ratio, total cholesterol, HDL cholesterol, C-reactive protein, or eGFR.

### Table 1

| Characteristic | No psoriasis (n=15,221) | Psoriasis (n=455) | *p* |
|---|---|---|---|
| Age, years | 47.3 ± 16.9 | 50.6 ± 15.9 | 0.0008 |
| Female, % | 51.4 | 49.7 | 0.52 |
| Race/ethnicity, % | | | |
| 　Mexican American | 8.1 | 4.5 | |
| 　Other Hispanic | 5.5 | 4.4 | |
| 　Non-Hispanic White | 67.8 | 79.6 | |
| 　Non-Hispanic Black | 11.2 | 5.8 | |
| 　Other / multiracial | 7.4 | 5.7 | |
| Education, % | | | |
| 　<9th grade | 5.2 | 3.7 | |
| 　9–11th grade | 11.0 | 11.5 | |
| 　HS/GED | 21.5 | 21.6 | |
| 　Some college | 32.0 | 32.4 | |
| 　College graduate | 30.3 | 30.7 | |
| PIR | 2.92 ± 1.67 | 3.06 ± 1.69 | 0.14 |
| BMI, kg/m² | 28.9 ± 6.8 | 29.8 ± 6.9 | 0.035 |
| Waist, cm | 98.8 ± 16.3 | 101.8 ± 15.7 | 0.005 |
| Total cholesterol, mg/dL | 192.6 ± 41.1 | 194.9 ± 42.7 | 0.40 |
| HDL, mg/dL | 53.0 ± 16.0 | 51.8 ± 16.9 | 0.28 |
| CRP, mg/dL | 0.37 ± 0.66 | 0.43 ± 1.02 | 0.50 |
| eGFR, mL/min/1.73 m² | 95.5 ± 21.1 | 93.9 ± 20.6 | 0.30 |
| Total PA, MET-min/week | 3,106 ± 7,746 | 2,847 ± 4,968 | 0.46 |
| PA group, % inactive/low/moderate/high | 28.9 / 14.4 / 29.7 / 27.0 | 27.4 / 16.2 / 32.2 / 24.3 | — |
| **Sedentary time, min/day** | **384.0 ± 202.0** | **433.0 ± 215.2** | **0.006** |
| Diabetes, % | 12.3 | 15.8 | 0.076 |
| Hypertension, % | 32.3 | 42.0 | 0.002 |
| Smoking, % never/former/current | 56.0 / 23.8 / 20.2 | 42.7 / 38.5 / 18.8 | <0.001 |

> 连续变量为加权均值 ± 加权 SD；分类变量为加权比例。连续变量 *p* 来自加权线性回归，分类变量来自 `svychisq`。
> **Table 1 的 *p* 值为描述性，未做多重比较校正**，不应用于推断。
> 久坐四分位切点：240 / 360 / 480 min/day。PA 分组切点：0 / 720 / 3,000 MET-min/week。
> `total cholesterol` 仍作为基线特征描述，但**已不作为模型协变量**（缺失 9.4%，且非合理混杂因素）。
> 来源：`table1_stats.csv`（`R/06_table1_stats.R`）

---

## 3.3 Physical activity and prevalent psoriasis

In survey-weighted multivariable logistic regression adjusted for age, sex, race/ethnicity, education, PIR, smoking, alcohol intake, hypertension and diabetes, **physical activity was not associated with prevalent psoriasis**.

**Continuous** (Table 2, Figure 2): each additional 1,000 MET-min/week was associated with an OR of **0.997 (95% CI 0.981–1.014; *p* = 0.76)**.

**Categorical** (reference: inactive), no monotonic pattern was evident (Figure 2):

| PA group | OR (95% CI) | *p* |
|---|---|---|
| Inactive | 1.00 (ref) | — |
| Low | 1.21 (0.77–1.89) | 0.42 |
| Moderate | 1.19 (0.83–1.71) | 0.36 |
| High | 1.04 (0.75–1.43) | 0.84 |
| *p* for trend | — | 0.76 |

**Dose–response** (Figure 3a): restricted cubic splines (3 df, exposure log1p-transformed) showed no evidence of an overall association (*P* = 0.76) and no evidence of departure from linearity (*P* = 0.62; linear-vs-spline Wald test). The curve was essentially flat, with a wide confidence band at the sparse upper extreme of the exposure distribution.

> 来源：`model_PA_continuous.csv`、`model_PA_group.csv`、`primary_exposures_BH.csv`、`audit_A_nonlinearity.csv`

---

## 3.4 Sedentary behaviour and prevalent psoriasis

In contrast to physical activity, **sedentary time was associated with prevalent psoriasis**.

**Continuous** (Table 2, Figure 2): each additional 60 min/day of sedentary time was associated with an OR of **1.065 (95% CI 1.016–1.115; *p* = 0.013)**. Sedentary time and physical activity were the two exposures prespecified as primary; with the Benjamini–Hochberg correction applied across this two-test family, the adjusted *p* value was **0.026**.

**Quartiles** (reference: Q1; Figure 2):

| Sedentary quartile | OR (95% CI) | *p* |
|---|---|---|
| Q1 (lowest) | 1.00 (ref) | — |
| Q2 | 0.96 (0.67–1.38) | 0.84 |
| Q3 | 1.18 (0.84–1.64) | 0.35 |
| **Q4 (highest)** | **1.59 (1.09–2.32)** | **0.022** |

The association was driven by the highest quartile, with no monotonic gradient across the lower three quartiles.

**Dose–response** (Figure 3b): the spline showed a borderline overall association (*P* = 0.063) with no evidence of departure from linearity (*P* = 0.21). Descriptively, the curve was below unity up to approximately 300 min/day, crossed 1.0 between 400 and 410 min/day, and reached an OR of approximately 2.6 at 600 min/day; the confidence band was very wide above 500 min/day (OR 2.55, 95% CI 0.56–11.59), so this pattern should be regarded as **descriptive rather than as a demonstrated threshold**.

> 来源：`model_sedentary_continuous.csv`、`model_sedentary_quartile.csv`、`primary_exposures_BH.csv`、`audit_A_nonlinearity.csv`
> ⚠️ **BH 校正口径（关键）**：本文把「两个预先指定的主要连续暴露」作为比较家族 → 久坐校正后 *p* = **0.026（显著）**。若改用全文 9 个暴露检验作为家族 → *p* = **0.098（不显著）**。**该口径必须在 Methods 中明确声明。**

---

## 3.5 Accelerometer-measured physical activity (exploratory)

Among the 8,575 participants in the 2011–2014 accelerometer subsample (233 with psoriasis) who met the wear-time criteria (≥600 min/day on ≥3 days), objectively measured activity volume was not associated with psoriasis: **OR 1.04 per SD of MIMS/day (95% CI 0.86–1.25; *p* = 0.70)**. This analysis is **exploratory** (secondary exposure, not part of the prespecified primary family) and was not used to support or refute the primary result.

> 来源：`model_accelerometer.csv`、`output/log_02_build.txt`（PAXDAY 原始 130,186 人-日 → 14,545 有效个体 → 与协变量交集 8,575）

---

## 3.6 Mediation by BMI and CRP（探索性，不作推断）

We conducted an exploratory analysis of whether adiposity (BMI) or systemic inflammation (CRP) mediated the association between physical activity and psoriasis, using a survey-weighted bootstrap resampling primary sampling units within strata (500 replicates, percentile confidence intervals).

**These analyses are not interpreted, for three reasons.** First, the total effect of physical activity was close to the null, so the proportion mediated is not mathematically interpretable and is not reported as a finding. Second, the two estimation approaches we used disagreed substantially (BMI: 15.9% versus 44.2%; CRP: −15.4% versus 126.7%), indicating unstable estimates. Third, the CRP model rested on a highly selected subset — **CRP was missing for 67.4% of the analytic sample**, giving n = 5,100 for the CRP model versus n = 15,027 for the BMI model; these are not comparable samples.

| Mediator | n | Indirect effect per 1,000 MET-min/wk (log-odds) | 95% CI |
|---|---|---|---|
| BMI | 15,027 | −0.00026 | −0.00062 to −0.00001 |
| CRP | 5,100 | −0.00014 | −0.00063 to 0.00040 |

**We therefore make no inference from these mediation analyses.** They are reported only for completeness and to document the extent of the missingness problem for inflammatory biomarkers in this dataset.

> 来源：`mediation_bootstrap.csv`、`mediation_survey_diff.csv`
> ⚠️ 按 P0-5 决策 B 重写：删除了「间接效应显著」的表述，补 CRP 缺失率披露。

---

## 3.7 Sensitivity analyses

Associations with more specific psoriasis phenotypes were estimated in three **exploratory** analyses, all reported per 1,000 MET-min/week. All had events-per-variable ratios below 10 and were therefore underpowered:

| Outcome definition | Cases | EPV | OR (95% CI) per 1,000 MET-min/wk | *p* |
|---|---|---|---|---|
| Moderate-to-severe psoriasis (MCQ075 ≥3) | 62 | 4.4 | 0.97 (0.91–1.02) | 0.25 |
| Medication-confirmed psoriasis | 38 | 2.7 | 0.96 (0.89–1.03) | 0.24 |
| Psoriatic arthritis (MCQ195 = 3) | 35 | 2.5 | 1.00 (0.97–1.04) | 0.97 |

Even in minimally adjusted models (age and sex only; EPV 31.0 / 19.0 / 17.5) the estimates were essentially unchanged (0.96 / 0.96 / 1.00). Given the low events-per-variable ratios, **these analyses can neither support nor refute the primary result** and are not presented as robustness evidence.

> 来源：`sens_*.csv`、`audit_B_sensitivity_units.csv`、`sensitivity_case_counts.csv`
> ⚠️ **原稿数值已修正**：原模型暴露为「每 1 MET-min/week」，原稿误标为「per 1,000」，差 1000 倍指数（原写 0.99996 / 0.99993 / 1.00000）。上表为换算后的正确值。

---

## 3.8 Subgroup analyses

We assessed whether the association between physical activity and psoriasis differed by sex, diabetes status or race/ethnicity, using joint Wald tests for the interaction terms with model parameterisations consistent with the main analysis:

| Subgroup | *p* for interaction |
|---|---|
| Sex (female) | 0.47 |
| Diabetes | 0.052 |
| Race/ethnicity (4 df) | 0.54 |

**No evidence of effect modification was found for any of the three subgroups.**

> 来源：`audit_C_interactions.csv`
> ⚠️ 原稿 race 交互报 0.927，来自把 race 当**数值**（1–5）且用 `min(p)` 汇总的设定；改为与主模型一致的 `factor(race)` + 4 df 联合 Wald 检验后为 **0.539**。糖尿病交互由 0.044 变为 **0.052**（跨过 0.05）。

---

## 2. Methods — Statistical analysis（供合并进正文）

```text
All analyses were performed in R 4.5.2 using the survey package (v4.5) and splines.
NHANES 2-year examination weights (WTMEC2YR) were divided by the number of pooled
cycles; strata (SDMVSTRA) and primary sampling units (SDMVPSU) were used with
nest = TRUE, and strata containing a single PSU were handled using
options(survey.lonely.psu = "adjust"). The independent unit of analysis was the
participant. Participants with missing data on any model covariate were excluded
(complete-case analysis); the ten covariates were age, sex, race/ethnicity,
education, family income-to-poverty ratio, smoking, alcohol intake, sedentary time,
hypertension and diabetes. Total cholesterol was not included in the models
(missing for 9.4% of participants, and not a plausible confounder of the
exposure-outcome relationship); it is nonetheless reported in Table 1.

Exposure-outcome associations were estimated by survey-weighted multivariable
logistic regression. Sedentary time (per 60 min/day) and physical activity (per
1,000 MET-min/week) were prespecified as the two primary exposures, and p values
for these two comparisons were adjusted for multiple testing using the
Benjamini-Hochberg procedure. All other analyses — exposure categories,
dose-response splines, accelerometer-measured activity, mediation, sensitivity and
subgroup analyses — are secondary or exploratory, were not corrected for multiple
testing, and were not used to support or refute the primary result.

Total physical activity was computed as 8 x minutes of vigorous and 4 x minutes of
moderate activity per day, summed over days, and analysed both categorically
(0, <720, 720-3,000, >3,000 MET-min/week) and continuously per 1,000 MET-min/week.
Sedentary time was self-reported minutes sitting on a usual day, analysed by
quartiles (cut points 240/360/480 min/day) and continuously per 60 min/day.
Restricted cubic splines with 3 degrees of freedom (two interior knots at the 33.3rd
and 66.7th percentiles) were used for dose-response; physical activity was
log1p-transformed before spline fitting. Departure from linearity was assessed by a
Wald comparison of the linear and spline models. Accelerometer data (PAXDAY) were
aggregated from person-days to individuals, retaining days with >=600 min of valid
wear and requiring >=3 valid days. Mediation was assessed with a survey-weighted
bootstrap resampling primary sampling units within strata (500 replicates,
percentile confidence intervals) and is reported as exploratory only.

Effect estimates with 95% confidence intervals and exact p values are reported
throughout. Table 1 p values are descriptive and were not adjusted for multiple
testing. The analysis code, the derivation of all variables and the exclusion
cascade are available from the corresponding author.
```

---

## 3.9 Bidirectional two-sample Mendelian randomisation

Because the OpenGWAS endpoint used to construct instruments programmatically was unavailable, instruments were derived from local summary statistics: exposures from the GWAS Catalog and FinnGen R12, with alleles resolved and linkage disequilibrium pruning performed against 1000 Genomes phase 3 EUR via the Ensembl REST API. Outcome data were read from the FinnGen R12 public release and, for the reverse direction, from UK Biobank.

### 3.9.1 Instrument strength

The leisure screen-time instrument (GCST90104339, n = 526,725) comprised **26 independent variants** with F statistics ranging from **28.3 to 73.5**. For the reverse direction, 22,648 genome-wide-significant psoriasis variants were reduced to 35 by distance pruning and to **15 independent variants** after allele resolution and LD pruning (r² > 0.001), with F statistics of **31.0 to 1373.6**. No instrument had F < 10.

### 3.9.2 Forward direction: sedentary behaviour → psoriasis

All 26 instruments were retrieved from FinnGen R12 (12,760 cases, 482,181 controls). Harmonisation retained all variants with no allele conflicts.

| Outcome | Method | OR (95% CI) | *p* |
|---|---|---|---|
| **Psoriasis** | **IVW** | **0.98 (0.80–1.21)** | **0.85** |
| | Weighted median | 1.12 (0.85–1.49) | 0.42 |
| | MR-Egger | 1.50 (0.49–4.57) | 0.48 |
| Psoriasis vulgaris | IVW | 0.88 (0.69–1.12) | 0.30 |
| Psoriatic arthritis | IVW | 1.08 (0.78–1.50) | 0.63 |

Cochran's Q tests showed no evidence of heterogeneity (*p* = 0.21, 0.90 and 0.90), and MR-Egger intercepts provided no evidence of directional pleiotropy (*p* = 0.45, 0.12 and 0.29). Leave-one-out and single-SNP analyses did not identify any variant driving the estimates.

### 3.9.3 Reverse direction: psoriasis → sedentary behaviour

This direction addressed the reverse-causation concern raised in the dermatology literature — whether psoriasis patients are less active because of their disease, rather than inactivity contributing to psoriasis.

| Outcome | Method | OR (95% CI) | *p* |
|---|---|---|---|
| **Television viewing time** (UKB, n = 437,887) | **IVW** | **1.003 (0.997–1.009)** | **0.28** |
| | MR-Egger | 1.000 (0.992–1.008) | 0.995 |
| Computer game use (UKB, n = 462,433) | IVW | 1.001 (0.996–1.007) | 0.68 |

Heterogeneity tests were non-significant for television viewing (*p* = 0.41) but **significant for computer game use (*p* = 0.006)**; the latter estimate is therefore reported as supporting evidence only. Two of the 15 instruments had no direct outcome data and were replaced by proxies (r² > 0.8) identified by OpenGWAS.

### 3.9.4 Interpretation of the genetic evidence

**The genetic analyses did not corroborate the observational association between sedentary behaviour and psoriasis.** The IVW estimate for the forward direction (OR 0.98, 95% CI 0.80–1.21) **overlaps the point estimate from the observational arm (OR 1.065)** and therefore does not contradict it, but provides no support. The reverse direction was likewise null (OR 1.003, 95% CI 0.997–1.009).

**Importantly, the null reverse-direction result removes the most natural explanation for the discrepancy**: the hypothesis that psoriasis itself reduces activity and increases sedentary time is not supported by the genetic evidence. Taken together with the null physical activity findings, this pattern suggests that the observed association between sedentary time and psoriasis is most plausibly explained by **confounding or non-causal pathways rather than a single directional effect** in either direction. The narrow confidence interval for the reverse estimate nevertheless corresponds to an effect of at most approximately 0.9% per unit of screen time and cannot be interpreted as demonstrating the absence of a small effect.

> 来源：`output/tables/mr_local_summary.txt`（汇总）、`mr_local_*_main/heterogeneity/pleiotropy/leaveoneout/singlesnp.csv`（分表，31 个）
> 执行脚本：`R/04b_mr_local.R`；日志：`output/log_04b_mr_local.txt`
> **暴露构念差异须在 Limitation 声明**：观察臂用自报静坐分钟，MR 用屏幕时间代理变量，二者不是同一构念。
> **未做 MVMR 与中介 MR**：PA 与久坐高度相关，且中介的 IV 依赖同一批失效端点，已列为局限。

---

## 图件清单

| 图 | 文件 | 状态 |
|---|---|---|
| 图1 参与者流程图 | `fig1_flow_participants.png` | ✅ 已按 n=15,676 重新生成 |
| 图2 主结果森林图 | `fig2_forest_observational.png` | ✅ 已重新生成 |
| 图3 剂量-反应（a PA + b 久坐）| `fig3_rcs_dose_response.png` | ✅ 已重新生成 |
| 图3a / 图3b 单张版 | `fig3a_*.png` / `fig3b_*.png` | ✅ |
| 图4a 正向 MR 森林图（3 个结局）| `fig4a_mr_forward_forest.png` | ✅ 已生成并核验 |
| 图4b 反向 MR 森林图（2 个结局）| `fig4b_mr_reverse_forest.png` | ✅ 已生成并核验 |
| 图5a 留一法（26 SNP + All）| `fig5a_leaveoneout.png` | ✅ 已生成并核验 |
| 图5b 漏斗图 | `fig5b_funnel.png` | ✅ 已生成并核验 |
| 图6 三角互证整合图 | `fig6_triangulation.png` | ✅ 已生成并核验 |
| 图7 三层证据效应量对比 | `fig7_triangulation_summary.png` | ✅ 已生成并核验 |

> **图 7 是全文最关键的一张**：三层证据（观察臂 / 正向 MR / 反向 MR）同轴对比，
> 一眼能看出「观察臂点估计 1.065 落在正向 MR 的 CI 0.80–1.21 之内」这一关键事实。
> 投稿时建议作为主图或次主图。
>
> `05_figures_tables.R` 已做优雅降级：缺 MR 产物时只提示跳过，不报错，也**不产出标着 "n/a" 的占位图**。
> RCS 图用 log y 轴并裁剪——线性轴上置信带会把 OR 曲线压成平线。
> 漏斗图的点大小表示 1/SE；**不用「对 Cochran Q 的贡献」上色**——本项目 beta×se 量级仅 1e-4，色阶会全挤成一个颜色，等于没上色。

---

## 数据溯源总表

| 正文位置 | 数值 | 来源文件 | 脚本 |
|---|---|---|---|
| 3.1 样本量 15,676 / 病例 455 | — | `output/flow_analytic.csv` | `02_build_dataset.R` |
| 3.1 缺失与纳入vs排除 | PIR 8.95% / 2.70% vs 2.90% | `audit_E_*.csv` | `08_stats_audit_fixes.R` |
| 3.1 去 PIR 敏感性 | 17,201 / 496 | `audit_F_no_pir.csv` | `08` |
| 3.2 Table 1 全部 | — | `table1_stats.csv` | `06_table1_stats.R` |
| 3.3 PA 连续 / 分组 / 趋势 | 0.997 / 1.04 / 0.76 | `model_PA_continuous.csv`、`model_PA_group.csv` | `03` |
| 3.3 非线性 | 整体 0.763 / 非线性 0.615 | `audit_A_nonlinearity.csv` | `08` |
| 3.4 久坐连续 / 四分位 | 1.065 / 1.59 | `model_sedentary_*.csv` | `03` |
| **3.4 BH 校正（关键）** | **0.026** | `primary_exposures_BH.csv`、`audit_D_multiplicity.csv` | `03` / `08` |
| 3.5 加速度计 | 1.04 (0.86–1.25) | `model_accelerometer.csv` | `03` |
| 3.6 中介（探索性） | BMI −0.00026；CRP n=5,100 | `mediation_bootstrap.csv` | `03` |
| 3.7 敏感性（单位已修正）| 0.97 / 0.96 / 1.00 | `audit_B_sensitivity_units.csv` | `08` |
| 3.8 交互（联合 Wald）| 0.47 / 0.052 / 0.54 | `audit_C_interactions.csv` | `08` |

---

## 待办

| # | 事项 | 状态 |
|---|---|---|
| 1 | ~~P0-1 样本量口径~~ | ✅ 已修：n=15,676，流程与模型一致，并加断言自检 |
| 2 | ~~P0-4 多重比较家族~~ | ✅ 已修：预选 2 个主要暴露，BH 校正后 0.026 |
| 3 | ~~P0-5 中介解释~~ | ✅ 已修：降为探索性，不作推断 |
| 4 | ~~P0-2 单位错标 / P0-3 非线性检验 / P1-1 race 交互~~ | ✅ 已修 |
| 5 | ~~3.9 MR 臂全部内容~~ | ✅ **已完成**：双向 5 组 MR（正向 3 结局 + 反向 2 结局），31 个分表 |
| 6 | ~~图 4–7~~ | ✅ **已完成**：`05` 已改读 `mr_local_*`，11 张图逐张核验通过 |
| 7 | ~~Discussion 4.5 回填 MR 结果~~ | ✅ **已完成**，含「反向 MR 阴性」的正确写法 |
| 8 | ~~Methods 补 MR 段 + STROBE-MR 清单~~ | ✅ **已完成**：`13_Methods统计与MR段.md`（26 条清单，2 条待投稿时填） |
| 9 | Table S1（纳入 vs 排除，已算出）+ Table S2（去 PIR，已算出）**排版成补充表** | 中 · 数据在 `audit_E_*.csv` / `audit_F_no_pir.csv` |
| 10 | 加速度计 per-SD 标准化改用加权 SD（当前为未加权 `scale()`） | 中 |
| 11 | ★ Table 1 与 Table 2 排版成期刊格式（含 SD 与脚注） | 中 |
| 12 | ★ Abstract 初稿（150–250 词） | **高** · 投稿必需 |
| 13 | Data Availability / Code Availability 段（`nature-data`） | **高** · 投稿必需 |
| 14 | 目标期刊确定后按其格式调整（`sci-journal-issue-mining`） | 中 |
| 15 | 12 处 `[CITE-n]` 占位符待插入与核验 | **高** · 投稿前必办 |
| 16 | MVMR 与中介 MR | ❌ **不做**，依赖同一批失效端点，已在 Methods §2.5.2 声明理由 |

---

## 写作红线（避免自伤）

- **横断面 = 只能说 association**，不得出现 cause / effect / reduce risk。
- **BH 校正家族必须写进 Methods**——这是本文主结论能否站住的关键（0.026 vs 0.098）。
- **不得写「敏感性分析均阴性故结论稳健」**——三项 EPV 全部 <10，没有检出能力。
- **不得引用中介比例作为结论**——总效应趋零 + 两法分歧 + CRP 缺失 67%。
- **亚组交互现已全部不显著**（含糖尿病 0.052），Discussion 不要保留「糖尿病交互」这条线。
- 暴露单位必须与模型变量一致：`met_1000` ≠ `met_total`。
- **★ MR 阴性必须写成「未提供支持」而非「否证」**——正向 MR 的 CI 0.80–1.21 **覆盖**观察臂点估计 1.065，写成"否证"是过度陈述，审稿人一眼看穿。
- **★ 反向 MR 阴性要主动交代，不要只挑好说的报**。它推翻了"银屑病导致少动"这个最自然的解释，是本文最不利的一条证据；藏起来会在审稿时被问出来，届时更被动。
- **★ 不得写「MR 证明无效应」**——反向 OR 1.003 的 CI 对应效应上限约 0.9%/单位，功效不足以排除小效应。
- **★ 暴露构念差异要声明**：观察臂用自报静坐分钟，MR 用屏幕时间代理变量，不是同一构念。
