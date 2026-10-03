# 1. Introduction（英文投稿版）

> 供主稿 §1 使用。全部论断由 `15_参考文献表.md` 中已核验的 12 条文献支撑。
> 编号 CITE-n 对应参考文献表；投稿时按目标期刊的引用格式转换。
> **引言末尾必须写明预设假设**（本项目的分析计划已预先指定主要暴露与校正家族）。

---

## 1. Introduction

Psoriasis is a chronic, immune-mediated inflammatory disease affecting approximately
2–3% of the population in Europe and North America. Beyond its visible skin
manifestations, psoriasis carries a substantial systemic burden, including
cardiovascular comorbidity, metabolic dysfunction and accelerated arterial
stiffening (Miller et al., 2013; Takeshita et al., 2017). It is also a chronic,
relapsing disease that impairs quality of life, places a substantial burden on
healthcare systems, and is associated with meaningful psychological distress. Given
the scale of this burden, identifying modifiable factors that influence disease
activity — or that might in turn be altered by having the disease — has become a
reasonable target for public health research.

Physical activity has attracted considerable interest in this context. The
physiological plausibility is strong: physical inactivity is a recognised primary
cause of chronic disease, operating through impaired endothelial function, reduced
lipolysis and vascular remodelling (Booth et al., 2012), and the inflammatory and
metabolic dysregulation characteristic of psoriasis (Takeshita et al., 2017) overlaps
with the pathways that inactivity is known to influence. The empirical literature,
however, is inconsistent. A cross-sectional analysis of US adults reported a lower
prevalence of psoriasis among those meeting physical activity recommendations, whereas
other observational studies have found no such association (Zheng et al., 2018).
Systematic synthesis points the same way: a recent meta-analysis of weight-loss
interventions concluded that the available intervention evidence remains insufficient
to establish an effect on psoriasis severity (Morrow et al., 2026).

A second observation compounds this uncertainty. Much of the literature frames the
question in the reverse direction — asking whether patients with psoriasis are less
active than those without — rather than whether activity influences disease
characteristics. An earlier NHANES analysis adopted exactly that framing (Do et al.,
2015), and a recent cross-sectional study of psoriasis patients explicitly identified
the underlying problem as a "classic chicken-and-egg dilemma": are patients more active
because their psoriasis is milder, or is milder psoriasis a consequence of greater
activity? The authors concluded that establishing causality "would require randomized
controlled trials" (Andersen et al., 2026). This is a genuine impasse for
cross-sectional research, and no analytic adjustment can resolve it, because
adjustment cannot recover temporal ordering that was never measured.

**A third issue complicates interpretation further: physical activity and sedentary
behaviour are usually treated as interchangeable, but they are not.** The two are
distinct exposures with partly independent pathways. The dissociation is well
documented for other health outcomes: a harmonised meta-analysis of more than one
million adults showed that the detrimental association of sitting time with
mortality is only partly attenuated by physical activity, and is largely abolished at
the highest activity levels (Ekelund et al., 2016). The physiological consequences of
sedentary behaviour are now well characterised — prolonged sitting impairs skeletal
muscle contractions, reduces postprandial glucose clearance, suppresses lipolysis and
shifts adipokine secretion toward a pro-inflammatory profile, with these effects
occurring in lean as well as obese individuals (Pinto et al., 2023). It is therefore
plausible that sedentary behaviour could be associated with psoriasis independently of
whether an individual meets physical activity recommendations. To our knowledge, this
has not been examined: the two exposures have not been evaluated side by side against
psoriasis, nor has the direction of the association been tested genetically in both
directions.

**We therefore designed a triangulation study.** The observational arm compared
sedentary time and physical activity as separately prespecified exposures in a
nationally representative sample, using survey-weighted regression with restricted
cubic splines and objective accelerometer measurement as a second, differently
structured measure of activity. The genetic arm applied **bidirectional** two-sample
Mendelian randomisation, which is the only available design that can inform the
direction of an association between two traits (Lawlor et al., 2008;
van Kippersluis & Rietveld, 2018), using a screen-time instrument derived from the
largest published genome-wide association analysis of physical activity and sedentary
behaviour (Wang et al., 2022).

**The hypotheses were prespecified as follows.** The primary hypothesis was that
sedentary time would be positively associated with prevalent psoriasis, independent of
physical activity. The secondary hypothesis was that physical activity would *not* be
associated with psoriasis when modelled jointly with sedentary time, implying a
dissociation between the two exposures. The genetic hypothesis — stated before
analysis and reported whatever the outcome — was that Mendelian randomisation would
not corroborate the observational association in either direction, and that the
reverse direction would not support the reverse-causation explanation that
cross-sectional data alone cannot exclude.

Addressing all three layers matters because each has a different failure mode. An
association alone cannot establish direction. A null genetic result, however, is
interpretable in more than one way — it may indicate no causal effect, insufficient
power, or a mismatch between the genetic instrument and the exposure of interest —
and reporting it requires stating which of these applies. Setting out the hypotheses
in advance, and committing to reporting the genetic results whatever they show, is
what allows the combined evidence to be weighed rather than selectively narrated.

---

## 引言的结构说明（供撰写时参考，投稿时可删）

| 段 | 作用 | 引用 |
|---|---|---|
| ¶1 疾病负担与共病 | 建立重要性 | CITE-7（JAAD 共病）、CITE-9（心血管 meta）|
| ¶2 活动—银屑病的证据与矛盾 | 提出问题 | CITE-1（Medicine 2018）、CITE-3（JEADV 2026 meta）|
| ¶3 反向因果的困境 | 引出设计动机 | CITE-2（J Dermatol 2015）、CITE-4（JAAD 2026 chicken-and-egg）|
| ¶4 久坐是独立暴露 | **本文的差异化** | CITE-5（Lancet 2021 meta）、CITE-6（Physiol Rev 2023）、CITE-8（Compr Physiol 2012）|
| ¶5 三角互证设计 | 交代方法学依据 | CITE-10、11（MR 方法学）、CITE-12（Nat Genet 2022 工具变量来源）|
| ¶6 预设假设 | **必须保留** | — |

## 与后文的对应关系

- ¶2 承诺"证据不一致" → Discussion §4.2 逐条回应
- ¶3 承诺"鸡与蛋"困境 → Methods §2.5.3 的**结果解读预设规则**；
  Discussion §4.4–4.5 给出答案（**反向 MR 阴性推翻了反向因果解释**）
- ¶4 承诺"久坐是独立暴露" → Results §3.3（PA 阴性）vs §3.4（久坐阳性）
- ¶6 预设"MR 不会佐证" → Results §3.9.4 如实报告两个方向均阴性

> ⚠️ **写作红线**：
> 1. **不得**在引言里预告"我们证明了久坐导致银屑病"——本研究只有 association。
> 2. 预设假设段必须写明"报告遗传结果无论方向如何"（commitment to report），
>    这是本文可信度的关键，也是审稿人评估"选择性报告"的依据。
> 3. ¶4 的"to our knowledge"要保留限定词，定刊后若已有更新研究需改写。
