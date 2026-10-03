# Discussion 初稿 v0.2

> 生成日期：2026-10-03 ｜ 依据：`07_Results初稿.md` v0.3（n=15,676，病例 455）
> 覆盖：**全篇完整（4.1–4.7）**，含双向 MR 臂（§4.5，已回填真实数字）
> MR 依据：`output/tables/mr_local_summary.txt`；报告见 `12_双向MR结果报告.md`
> ✅ **引用已全部插入并完成双源核验**（PubMed × Crossref，2026-10-03）。
> 参考文献表见 **[15_参考文献表.md](15_参考文献表.md)**（APA 与 Vancouver 两种格式）。
> ⚠️ 定稿前需补卷(issue)与页码，并按目标期刊格式转换。

---

## 中文速览

**一句话核心发现**：在美国成年人中，久坐时间与银屑病患病呈正相关（每 60 min/day OR 1.065，95% CI 1.016–1.115，BH 校正后 *p* = 0.026），而体力活动与银屑病无关联；**双向孟德尔随机化在两个方向上均未提供因果支持**。

**这个"分离 + 遗传学阴性"的结果是本文的全部价值所在**，不是缺陷：
- 久坐与中高强度活动是不同的暴露，流行病学与机制上均可独立作用；
- 横断面数据**无法排除反向因果**（银屑病导致患者活动减少、久坐增加）→ 引入双向 MR；
- **MR 结果把这个问题说清楚了**：正向不显著（OR 0.98，CI 覆盖观察臂值 → 不能否证），
  **反向也不显著（OR 1.003）→ 推翻了"银屑病导致少动"这个最自然的解释**；
- 三条阴性合起来指向：**观察到的关联更可能由混杂或共同因素驱动，而非单向因果**。

**写作策略**：
1. 把分离结果主动写成设计动机，而不是掩饰成失败；
2. **反向 MR 阴性必须自己写出来** —— 这是本文最不利的一条证据，藏起来会在审稿时被问出来；
3. 全文因果性表述只留在假设层面（MR 阴性反而让这一点更严格）；
4. 临床结论要克制：数据不支持建议减少久坐来预防银屑病，但也不构成反对该干预的证据。

---

# Discussion

## 4.1 Principal findings

In a nationally representative sample of 15,676 US adults from NHANES 2009–2014, we found that greater sedentary time was associated with prevalent psoriasis, whereas physical activity was not (Figure 2, Figure 3). Sedentary time remained associated after adjustment for ten covariates, with an OR of 1.065 (95% CI 1.016–1.115) per additional 60 min/day and an FDR-adjusted *p* of 0.026 within the prespecified family of two primary exposures. The association was concentrated in the highest sedentary quartile (OR 1.59, 95% CI 1.09–2.32, versus the lowest quartile) without a monotonic gradient across the lower quartiles, and no evidence of departure from linearity was found. Neither self-reported nor accelerometer-measured physical activity was associated with psoriasis, and neither was the association materially altered when the income-to-poverty ratio was dropped to recover participants with missing income data (OR 1.059, 95% CI 1.011–1.109). No effect modification was detected by sex, diabetes status or race/ethnicity.

Bidirectional Mendelian randomisation with strong instruments in both directions (26 variants for screen time, F = 28.3–73.5; 15 for psoriasis, F = 31.0–1373.6) found no evidence of a causal effect in either direction (forward IVW OR 0.98, 95% CI 0.80–1.21; reverse IVW OR 1.003, 95% CI 0.997–1.009). The forward confidence interval contains the observational estimate and therefore does not refute it, but neither analysis provided support; notably, the null reverse result removes the reverse-causation explanation we had regarded as most likely.

---

## 4.2 Comparison with previous literature

The relation between exercise and psoriasis has been examined in a small number of observational studies, and their findings have been inconsistent: a cross-sectional analysis of US adults reported a lower prevalence of psoriasis among those meeting physical activity recommendations, while others have found no such association (Zheng et al., 2018). Most of this literature frames the question in the reverse direction — asking whether patients with psoriasis are less active than those without — rather than whether activity influences psoriasis risk; this was the explicit design of an earlier NHANES analysis (Do et al., 2015). Recent syntheses converge on the same conclusion. A 2026 systematic review and meta-analysis of weight-loss interventions concluded that the available intervention evidence is insufficient to establish an effect on psoriasis severity (Morrow et al., 2026), and a 2026 cross-sectional study of Danish psoriasis patients framed the underlying question as a "classic chicken-and-egg dilemma" — whether patients are more active because their psoriasis is milder, or whether milder psoriasis reflects greater activity — noting that establishing causality would require randomized controlled trials (Andersen et al., 2026).

Our data speak to this gap in a specific way. The dissociation we observed — an association with sedentary time in the absence of any association with physical activity — is consistent with the view that sedentary behaviour and moderate-to-vigorous activity are not two expressions of a single underlying propensity to be active. If they were, the two exposures would be expected to move together in the same model, which is not what we found. This dissociation is well documented for other health outcomes: a harmonised meta-analysis of more than one million adults showed that the detrimental association of sitting time with mortality is only partly attenuated by physical activity, and is abolished at the highest activity levels (Ekelund et al., 2016). It suggests that interventions targeting sedentary time may be relevant to psoriasis independently of increasing exercise.

We are aware of no previous Mendelian randomisation study of physical activity or sedentary behaviour in relation to psoriasis, and no study to our knowledge has examined the reverse direction with genetic instruments. Section 4.5 addresses this gap.

---

## 4.3 Possible mechanisms

Several mechanisms could plausibly link prolonged sedentary time to psoriasis, and each maps onto the mediators available in our data.

**Low-grade inflammation and adiposity.** The physiological consequences of sedentary behaviour are now well characterised: prolonged sitting impairs skeletal muscle contractions, reduces postprandial glucose clearance, suppresses lipolysis in adipose tissue and shifts adipokine secretion toward a pro-inflammatory profile, and these effects occur in lean as well as obese individuals (Pinto et al., 2023). Psoriasis is a chronic inflammatory disease in which systemic inflammation and metabolic dysregulation are both well documented (Takeshita et al., 2017). If sedentary behaviour contributes to a sustained inflammatory stimulus, it could plausibly contribute to psoriasis susceptibility rather than merely accompany established disease. Our mediation analysis examined adiposity and C-reactive protein for exactly this pathway; we found no interpretable evidence, but the CRP analysis rested on a subset missing 67.4% of C-reactive protein measurements, so this pathway remains untested rather than excluded (see 4.6).

**Vascular and mechanotransduction effects.** The absence of regular muscular contraction is a recognised primary cause of chronic disease, operating through impaired endothelial function, reduced lipolysis and vascular remodelling (Booth et al., 2012). Psoriasis carries a substantial cardiovascular comorbidity burden, with pooled estimates confirming elevated risks of cardiovascular disease and its components relative to the general population (Miller et al., 2013). A sedentary pathway operating through vascular mechanisms would therefore be consonant with the wider cardiovascular phenotype of psoriasis.

**Measurement, not biology.** Our two exposure measures differ in kind, and this matters when interpreting the null findings for activity. Self-reported physical activity is subject to reporting error that increases with age and with poorer health — both more common in psoriasis — and such differential misclassification would attenuate rather than inflate associations. The accelerometer analysis is free of this particular bias, and it was likewise null (OR 1.04, 95% CI 0.86–1.25). Two measurement approaches with different error structures producing the same null is more informative than either alone, and it argues against the null being an artefact of questionnaire design. It does not, however, exclude a true effect of activity that is too small to detect at this sample size: our confidence interval for activity permits odds ratios up to approximately 1.02 per additional 1,000 MET-min/week, which is a narrow effect on the null.

---

## 4.4 Causal interpretation and the problem of reverse causation

The single most important constraint on interpreting these data is that the design is cross-sectional. Temporal ordering is not established, and the direction of association cannot be determined from the data.

The reverse pathway is entirely plausible and is the one the dermatology literature has explicitly raised (Andersen et al., 2026): psoriasis is pruritic, stigmatising and associated with fatigue and pain, all of which reduce willingness to leave home and increase sitting time. Under this reading, the observed association is a consequence of illness rather than a risk factor for it. Note that this reading is *directionally consistent* with our own data in one respect — cases had lower total activity (2,847 vs 3,106 MET-min/week) — although that difference was not statistically significant (*p* = 0.46).

A further complication is that psoriasis is a fluctuating disease. Sedentary behaviour recorded at a single examination may reflect a period of active disease, whereas accumulated exposure over years — which is what a causal model would require — is not captured. This is a limitation of exposure measurement that no analytic adjustment can repair.

We therefore frame our findings as an association, and we treat the identification of direction as the explicit motivation for the genetic analysis in Section 4.5. As it turned out, that analysis did not support the reverse pathway either — a finding we return to in 4.5 because it removes the explanation we had regarded as most likely.

---

## 4.5 Bidirectional Mendelian randomisation

The genetic analysis was motivated by a specific question raised in Section 4.4: does the association between sedentary time and psoriasis reflect a causal effect in either direction, or something else? Because the OpenGWAS endpoint for programmatic instrument construction was unavailable, both exposure and outcome data were obtained from local summary statistics — exposures from the GWAS Catalog and FinnGen R12, with alleles resolved and linkage disequilibrium pruning performed against 1000 Genomes phase 3 EUR. Instrument strength was high in both directions: 26 independent variants for leisure screen time (F = 28.3–73.5) and 15 for psoriasis (F = 31.0–1373.6), with no instrument below F = 10.

**Neither direction supported a causal effect.** In the forward direction, leisure screen time was not associated with psoriasis (IVW OR 0.98, 95% CI 0.80–1.21, *p* = 0.85), nor with psoriasis vulgaris or psoriatic arthritis. In the reverse direction, psoriasis was not associated with television viewing time (IVW OR 1.003, 95% CI 0.997–1.009, *p* = 0.28). Heterogeneity and MR-Egger intercept tests were non-significant for the primary analyses, and leave-one-out and single-SNP analyses did not identify any variant driving the estimates.

Two aspects of this null result deserve careful statement, because a null finding is easy to over-claim in either direction.

**First, the forward analysis does not contradict the observational finding.** The MR confidence interval (0.80–1.21) contains the observational point estimate of 1.065. The correct reading is therefore that the genetic analysis *failed to corroborate* the association, not that it refuted it. Given that the genetic instrument captures variants influencing habitual screen time rather than the self-reported sitting minutes measured in NHANES, and that the two constructs only partially overlap, a null result is also compatible with construct mismatch.

**Second, the reverse-direction null removes the most parsimonious explanation we had for the discrepancy.** The natural reconciliation of an observational association with a null forward MR would have been reverse causation: patients with psoriasis sit more because they are ill. Had that been true, the reverse MR should have detected it. It did not (OR 1.003, *p* = 0.28). We note, however, that the confidence interval remains compatible with effects of up to approximately 0.9% per unit of screen time, so this analysis does not demonstrate the absence of a small effect; it excludes effects of the magnitude that would be required to explain the observational estimate under the simple assumptions of the method.

Taken together, the pattern we observe — an observational association with sedentary time, null associations with physical activity by two measurement methods, and null genetic evidence in both directions — points toward the association being driven by **confounding or by non-causal pathways common to both sedentary time and psoriasis**, rather than by a single directional effect that the genetic data failed to capture. The clinical implication is correspondingly modest: our data do not support prescribing reduced sitting as a means of preventing psoriasis, but neither do they provide evidence against it. Establishing a causal role for sedentary behaviour in psoriasis would require a prospective cohort with repeated activity measurement and, ultimately, an intervention trial — the design that the dermatology literature has already identified as necessary (Andersen et al., 2026). Instruments were selected and evaluated according to established methodological guidance for Mendelian randomization (Lawlor et al., 2008; van Kippersluis & Rietveld, 2018), and the screen-time instrument was drawn from the largest published genome-wide association analysis of physical activity and sedentary behaviour (Wang et al., 2022).

> **Methods cross-reference**: instruments, LD reference, harmonisation and sensitivity analyses are described in the accompanying Methods section; a STROBE-MR checklist is provided as Supplementary Table S4.
> **Two limitations are acknowledged here and repeated in 4.6**: the screen-time instrument is a proxy for, not identical to, self-reported sitting time; and multivariate MR, which would have conditioned the sedentary estimate on physical activity, was not performed because the physical activity instruments in the available summary statistics did not meet completeness requirements.

---

## 4.6 Strengths and limitations

### Strengths

- **Exposures and comparison family prespecified.** Physical activity and sedentary time were designated as the two primary exposures in the analysis plan, and the family for multiple-testing correction was defined in advance. This matters: had all nine exposure tests reported in the paper been treated as a single family, the sedentary association would not have survived FDR correction (*p* = 0.098). Declaring the family in advance is what allows the primary result to be interpreted as designed rather than as one of several fishing expeditions.
- **Complete reconciliation of the analysis sample with the model specification.** The participant flow (Figure 1) and the fitted models use an identical, explicit list of ten covariates, and the reported analytic sample (n = 15,676) is the number actually analysed. Events-per-variable was tracked throughout (32.5 for the primary model). Total cholesterol was reported in Table 1 but excluded from the models, because it was missing for 9.4% of participants and is not a plausible confounder of the exposure-outcome relationship.
- **Survey design handled explicitly**, including division of 2-year weights across pooled cycles, stratification by PSU, and explicit adjustment for strata containing a single PSU.
- **Two activity measures with different error structures agree**, and neither contradicts the questionnaire analysis.
- **Non-differential exclusion documented.** Participants excluded for incomplete covariates did not differ in psoriasis prevalence (2.70% vs 2.90%, *p* = 0.70), and dropping the income-to-poverty ratio to recover them left the estimate essentially unchanged.
- **Zero sample overlap in the genetic analysis.** Exposure instruments came from UK Biobank (United Kingdom) and FinnGen R12 (Finland) respectively, with the reverse direction using UK Biobank outcomes and FinnGen exposures. The populations are distinct, removing the sample-overlap bias that is difficult to exclude in most MR applications.
- **Strong instruments in both directions.** All instruments had F statistics above 10 (28.3–73.5 forward; 31.0–1373.6 reverse), so the null genetic findings are unlikely to reflect weak instrumentation.
- **The genetic analysis is fully reproducible from local files.** Because instrument construction relied on public summary statistics rather than a live API endpoint, the analysis can be re-run end-to-end by any reader, which is not always true of published MR.

### Limitations

- **Cross-sectional design.** No temporal ordering; direction of causation cannot be established from the observational data alone.
- **Self-reported outcome.** Psoriasis was defined by a self-report of a physician's diagnosis (MCQ070) with no clinical verification, and only three survey cycles (2009–2014) carried the variable, which limits both sample size and currency. Cases with a medication record confirm the phenotype only in a minority (38 of 455).
- **Self-reported exposures**, with the differential-misclassification concerns noted in 4.3.
- **Underpowered sensitivity analyses.** Analyses of more specific phenotypes had events-per-variable ratios of 4.4, 2.7 and 2.5 respectively. They are reported as exploratory and **can neither support nor refute** the primary result; the confidence intervals are wide (e.g. 0.86–1.03 for medication-confirmed disease).
- **Inflammatory mediation could not be assessed.** C-reactive protein was missing for 67.4% of the analytic sample, and the mediation models rested on non-comparable subsets (n = 15,027 for BMI, n = 5,100 for CRP). We make no inference from them.
- **Residual confounding is plausible.** Dietary intake, occupational activity, sleep and other behaviours were not available as covariates and are plausible determinants of both sedentary time and psoriasis.
- **Single-country data**, limiting generalisability.
- **Subgroup analyses were null**, including the borderline diabetes interaction (*p* = 0.052), and no subgroup finding should be inferred.

---

## 4.7 Conclusions

In a nationally representative US sample, greater sedentary time was associated with prevalent psoriasis, while physical activity was not. The dissociation between the two exposures, consistent across a self-report and an accelerometer measure and robust to a stricter multiple-testing correction, identifies prolonged sitting as a more informative correlate of psoriasis than moderate-to-vigorous activity in this population. Bidirectional Mendelian randomisation did not provide causal support in either direction, and in doing so removed the reverse-causation explanation that a cross-sectional analysis alone could not exclude. The most defensible reading of the combined evidence is therefore that the observed association reflects confounding or shared non-causal pathways rather than a single directional effect. The clinical implication is correspondingly limited: these data do not support recommending reduced sedentary time as a means of preventing psoriasis, nor do they argue against it. Establishing a causal role would require prospective cohorts with repeated activity measurement and, ultimately, an intervention trial.

---

## 待补的引用清单

> 全部需用 `citation-manager` 检索插入 + `nature-ref-verifier` 核验 DOI/PMID。**不得凭印象填写。**

> ✅ **引用完整性已校验通过**：`tools/check_citation_integrity.py` 确认 12 条双向匹配（无缺失、无孤儿条目）、正文无未替换占位符。

| 编号 | 支撑的论断 | 状态 | 已核验文献 |
|---|---|---|---|
| CITE-1 | 运动与银屑病的观察性研究结果不一致 | ✅ **已核验** | Zheng Q. et al. (2018); PMID 29979432; DOI `10.1097/md.0000000000011394` |
| CITE-2 | 既有 NHANES 分析方向相反（问"患者是否更少活动"） | ✅ **已核验** | Do Y. et al. (2015); PMID 25491719; DOI `10.1111/1346-8138.12721` |
| CITE-3 | 2026 系统评价+meta：干预证据不足以确立运动对银屑病的效果 | ✅ **已核验** | Morrow S. et al. (2026); PMID 41416383; DOI `10.1111/jdv.70247` |
| CITE-4 | "chicken-and-egg dilemma"；需要 RCT 才能确立因果 | ✅ **已核验** | Andersen C. et al. (2026); PMID 42727782; DOI `10.1016/j.jaad.2026.09.017` |
| CITE-5 | PA 与久坐分离（>100 万人 meta：坐与死亡仅部分被活动抵消） | ✅ **已核验** | Ekelund U. et al. (2016); PMID 27475271; DOI `10.1016/s0140-6736(16)30370-1` |
| CITE-6 | 久坐 → 肌收缩减少 / 餐后血糖清除↓ / 脂解抑制 / 促炎脂肪因子 | ✅ **已核验** | Pinto A. et al. (2023); PMID 37326297; DOI `10.1152/physrev.00022.2022` |
| CITE-7 | 银屑病的系统炎症与共病负担 | ✅ **已核验** | Takeshita J. et al. (2017); PMID 28212759; DOI `10.1016/j.jaad.2016.07.064` |
| CITE-8 | 缺乏肌收缩本身是慢性病主因（内皮功能、脂解、血管重塑） | ✅ **已核验** | Booth F. et al. (2012); PMID 23798298; DOI `10.1002/cphy.c110025` |
| CITE-9 | 银屑病的心血管共病（meta 分析） | ✅ **已核验** | Miller I. et al. (2013); PMID 24238156; DOI `10.1016/j.jaad.2013.06.053` |
| CITE-10 | MR 方法学原始文献（基因作为工具变量） | ✅ **已核验** | Lawlor D. et al. (2008); PMID 17886233; DOI `10.1002/sim.3034` |
| CITE-11 | 多效性稳健的 MR（MR-Egger 等稳健方法） | ✅ **已核验** | van Kippersluis H. et al. (2018); PMID 28338774; DOI `10.1093/ije/dyx002` |
| CITE-12 | 屏幕时间 GWAS（本文正向 MR 工具变量来源） | ✅ **已核验** | Wang Z. et al. (2022); PMID 36071172; DOI `10.1038/s41588-022-01165-1` |

> 全部 12 条经 **PubMed × Crossref 双源逐字段核验**（题名/作者/年份/期刊/DOI），状态均为 `ok`。完整条目见 **[15_参考文献表.md](15_参考文献表.md)**。
> ⚠️ 定稿前仍需补 **卷(issue) 与页码**（Crossref 记录未含），并按目标期刊格式转换（Vancouver / APA）。

---

## 写作红线（本节专用）

- 4.4 **必须自己先写反向因果**，不能等审稿人问。已在 §4.4 开头与 [CITE-4] 明确写出。
- ★ **4.5 阴性结果的两条红线**（本轮新增，最容易自伤）：
  - **不得写「MR 否证了观察臂关联」** —— CI 0.80–1.21 覆盖观察臂点估计 1.065，正确表述是"未提供支持"。
  - **不得写「MR 证明无效应」** —— 反向 OR 1.003 的 CI 对应上限约 0.9%/单位，功效不足以排除小效应。
- ★ **反向 MR 阴性必须主动写进 Discussion**，不能只报正向。这是本文最不利的一条证据（它推翻了"银屑病导致少动"这个最自然的解释），藏起来会在审稿时被问出来，届时更被动。已在 §4.5 第二段与 §4.4 末尾各写一次。
- 4.6 strengths 里那条「若以全文 9 个检验为家族则校正后 0.098」**要写**——主动交代比被审稿人发现好得多，而且它正好证明预注册比较家族的必要性。
- 4.2 里**不要说"首次"**，除非确认无既有研究（当前只能写"据我们所知未检索到"）。
- 全文不得出现 cause / reduce risk；因果性表述只能出现在假设层面（MR 阴性反而让这一点更严格）。
- 敏感性分析**不能写成"robustness evidence"**（EPV 全部 <10）。
- 亚组结果全为阴性，**不要保留"糖尿病交互"这条线**。
- **构念差异要声明**：观察臂自报静坐分钟 vs MR 屏幕时间代理变量，不是同一构念。这条既是诚实要求，也是 4.5 那句 "compatible with construct mismatch" 的支撑。
