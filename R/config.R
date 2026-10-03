# ============================================================================
# config.R —— 全局配置：路径 / NHANES 变量映射 / 参数
# ----------------------------------------------------------------------------
# ★ 所有"需要核对后调整"的地方都集中在本文件，其余脚本不需要改。
#   运行方式（在项目根目录）：Rscript R/01_download_nhanes.R
# ============================================================================

## ---------- 0. 包库路径（★ 必须最先执行）------------------------------------
# 本机第三方包装在隔离库；不设 .libPaths 会去写 Program Files（需管理员权限，必失败）
ISOLATED_LIB <- "C:/Users/Lay/.workbuddy/binaries/R/library"
if (dir.exists(ISOLATED_LIB)) .libPaths(c(ISOLATED_LIB, .libPaths()))

## ---------- 0b. 路径 ---------------------------------------------------------
PROJ_DIR <- getwd()                       # 请确保工作目录 = 项目根目录
RAW_DIR  <- file.path(PROJ_DIR, "data", "raw")
OUT_DIR  <- file.path(PROJ_DIR, "output")
TAB_DIR  <- file.path(OUT_DIR, "tables")
FIG_DIR  <- file.path(OUT_DIR, "figures")
for (d in c(RAW_DIR, OUT_DIR, TAB_DIR, FIG_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

## ---------- 1. NHANES 周期 --------------------------------------------------
# ★ 银屑病方案：MCQ070 仅存在于 2009-2010(F) / 2011-2012(G) / 2013-2014(H)
#   （2009-2010 新增，2015-2016 停用）——见 04_可行性核查报告.md
#   原 MASLD 方案曾用 c("E","F","G","H","I","J")，已废弃
NHANES_CYCLES <- c("F", "G", "H")                     # 2009-2010, 2011-2012, 2013-2014
NHANES_YEARS  <- c("2009-2010", "2011-2012", "2013-2014")
PAM_CYCLES    <- c("G", "H")                          # 加速度计仅 2011-2014
ACC_PREFIX    <- "PAXDAY"                             # ★ 加速度计文件名前缀（实测非 PAM）

# ★ 有效天判定标准（PAXDAY 无现成的「有效天」标志，须自行设定并在方法中声明）
#   常用口径：单日有效佩戴 ≥10 小时（600 分钟）且至少 3 个有效天
ACC_MIN_VALID_MIN  <- 600
ACC_MIN_VALID_DAYS <- 3

## ---------- 2. 需下载的 NHANES 文件 ----------------------------------------
NHANES_FILES <- c(
  "DEMO",    # 人口学 + 抽样权重 + 妊娠状态
  "PAQ",     # 体力活动问卷
  "PAXDAY",  # ★ 加速度计日汇总文件（仅 G/H）。
             #   实测：NHANES 没有 "PAM_*" 文件；2011-2012 的加速度计文件名是
             #   PAXDAY_G（Day，日汇总）、PAXHD_G（Header）、PAXHR_G（Hour, 122MB）、
             #   PAXMIN_G（Minute, 7.6GB，仅 FTP）、PAX80_G（80Hz 原始）。
             #   本研究只需日汇总 → PAXDAY。
  "BIOPRO",  # 生化：ALT/AST/GGT/TG/总胆固醇
  "HDL",     # HDL 胆固醇（LBDHDD）
  "CRP",     # ★ C 反应蛋白 LBXCRP —— 独立文件，不在 BIOPRO 中（实测 2026-10-03）
  "BMX",     # BMI / 腰围
  "GHB",     # HbA1c
  "GLU",     # 空腹血糖
  "DIQ",     # 糖尿病问卷
  "BPQ",     # 血压问卷        ← 注意是 BPQ 不是 HBP
  "ALQ",     # 饮酒
  "SMQ",     # 吸烟
  "MCQ",     # 疾病史（含银屑病 MCQ070/075/195）
  "RXQ_RX",  # 处方药
  "INQ"      # 家庭收入（INQ 中没有 PIR；PIR=INDFMPIR 在 DEMO 中）
)

## ---------- 3. 变量映射表 ---------------------------------------------------
## ★★ 执行前请对照 NHANES 官方文档核对本表。若某变量缺失，脚本会自动跳过并告警。
VARMAP <- list(

  # --- 人口学 / 权重 ---
  age      = "RIDAGEYR",
  sex      = "RIAGENDR",       # 1=男 2=女
  race     = "RIDRETH1",       # 1=墨西哥裔 2=其他西裔 3=非西裔白人 4=非西裔黑人 5=其他
  edu      = "DMDEDUC2",       # 20-24 编码
  pir      = "INDFMPIR",
  preg     = "RIDEXPRG",
  wt_2yr   = "WTMEC2YR",       # 2 年 MEC 权重
  psu      = "SDMVPSU",
  strata   = "SDMVSTRA",

  # --- 体力活动问卷（PAQ）---
  pa_vig_work_yn = "PAQ605", pa_vig_work_d = "PAQ610", pa_vig_work_min = "PAD615",
  pa_mod_work_yn = "PAQ620", pa_mod_work_d = "PAQ625", pa_mod_work_min = "PAD630",
  pa_vig_rec_yn  = "PAQ650", pa_vig_rec_d  = "PAQ655", pa_vig_rec_min  = "PAD660",
  pa_mod_rec_yn  = "PAQ665", pa_mod_rec_d  = "PAQ670", pa_mod_rec_min  = "PAD675",
  sedentary_min  = "PAD680",   # 每日久坐分钟

  # --- 加速度计（PAXDAY：人-日级，仅 2011-2014）---
  # ★ 实测（2026-10-03）：NHANES 无 "PAM_*" 文件；正确文件为 PAXDAY_G/H。
  #   PAXDAY 是「一人一天一行」（最多 9 天），必须聚合到个体。
  #   该文件**没有强度分类变量**（sedentary/light/MVPA）；要强度须用分钟级
  #   PAXMIN_G（7.6 GB，仅 FTP）自行按阈值切分 —— 本研究不采用。
  acc_day_mims  = "PAXMTSD",  # Day sum: MIMS triaxial value ← 当日活动量
  acc_valid_min = "PAXVMD",   # 当日有效数据分钟数（0-1440）← 判定有效天
  acc_quality   = "PAXQFD",   # 质控标记计数
  acc_day_no    = "PAXDAYD",  # 佩戴第几天（1-9）

  # --- 生化（BIOPRO）---
  tg       = "LBXTR",     # 甘油三酯 mg/dL
  ggt      = "LBXSGTSI",  # GGT U/L
  alt      = "LBXSATSI",  # ALT U/L
  ast      = "LBXSASSI",  # AST U/L
  crp      = "LBXCRP",    # hs-CRP mg/dL
  chol     = "LBXSCH",    # 总胆固醇 mg/dL
  hdl      = "LBDHDD",    # HDL mg/dL
  scr      = "LBXSCR",    # 肌酐 mg/dL

  # --- 体格 ---
  bmi      = "BMXBMI",
  waist    = "BMXWAIST",

  # --- 糖代谢 ---
  hba1c    = "LBXGH",     # GHB
  glu_fast = "LBXGLU",    # GLU

  # --- 问卷 ---
  dm_told  = "DIQ010",    # 医生告知糖尿病
  htn_told = "BPQ020",    # 医生告知高血压
  smoke_100= "SMQ020",    # 吸过 100 支
  smoke_now= "SMQ040",    # 现在吸烟
  alc_12m  = "ALQ101",    # 过去 12 月是否饮酒
  alc_freq = "ALQ120Q",   # 饮酒频率
  alc_amt  = "ALQ130",    # 平均每日杯数

  # --- ★ 银屑病结局（MCQ，仅 2009-2014 存在）---
  psoriasis_ever   = "MCQ070",   # Ever been told you have psoriasis? (16-150y)
  psoriasis_degree = "MCQ075",   # Degree of psoriasis（1-4 级，仅 MCQ070=Yes 追问）
  arthritis_type   = "MCQ195"    # Which type of arthritis?（3 = Psoriatic arthritis）
)

## ---------- 4. MASLD 代理指标参数（⚠️ 原方案遗留，银屑病方案不使用）--------
FLI_CUT_PRIMARY   <- 60      # 主阈值
FLI_CUT_SENS      <- c(30, 60)
HSI_CUT           <- 36
USFLI_CUT         <- 30

## ---------- 5. 排除标准参数 -----------------------------------------------
ALC_HEAVY_F <- 20            # 女性 g/d
ALC_HEAVY_M <- 30            # 男性 g/d
AGE_MIN     <- 20

## ---------- 6. 肝毒性药物关键词（RXQ_RX 的 RXDDRUG 列匹配，小写）----------
HEPATOTOXIC_KEYWORDS <- c(
  "methotrexate", "amiodarone", "tamoxifen", "valpro", "isoniazid",
  "rifampin", "ketoconazole", "itraconazole", "azathioprine",
  "prednisolone", "prednisone", "carbamazepine", "phenytoin"
)

## ---------- 7. 抗糖尿病/降脂药关键词（用于敏感性分析）--------------------
METFORMIN_KEYWORDS <- c("metformin", "glucophage")

## ---------- 8. MR 数据集 ID --------------------------------------------------
# ✅ 2026-10-03 用 OpenGWAS API 逐个实测核对（tools/check_gwas_ids.py）
# ⚠️ 教训：此前据文献二手转写的 ID 有两处错误，务必以实测为准
MR <- list(

  # ---- 暴露 A：体力活动（GWAS Catalog，Klimentidis/Doherty 系列）----
  pa_mvpa      = "ebi-a-GCST006097",  # Moderate to vigorous PA levels (n=377,234) ★主暴露
  pa_vigorous  = "ebi-a-GCST006098",  # Vigorous PA (ncase=98,060)
  pa_accel     = "ebi-a-GCST006099",  # Accelerometer avg acceleration (n=91,084) ★客观测量

  # ---- 暴露 A'：自报体力活动（UK Biobank / Neale）----
  pa_walk_dur  = "ukb-b-16998",       # Duration of walks (n=395,831)  ← 不是"MVPA"！
  pa_walk_pace = "ukb-b-4711",        # Usual walking pace (n=459,915)
  pa_strenuous = "ukb-b-7663",        # Strenuous sports (n=460,376)
  pa_other_ex  = "ukb-b-8764",        # Other exercises (n=460,376)

  # ---- 暴露 B：久坐行为 ----
  # ★★ 2026-10-03 更正：GCST90104339 并非「无效 ID」，它是 GWAS Catalog 的
  #   Wang Z *Leisure screen time*（n=526,725），只是**不在 OpenGWAS 里**。
  #   「在 OpenGWAS 查不到」≠「ID 无效」——必须回原始数据库确认。
  #   B 路径（绕开 OpenGWAS）实测最优久坐暴露为 GCST010084（n=408,815，137 个 IV）。
  sedentary_tv   = "ukb-b-5192",      # Time spent watching television (n=437,887) ★主久坐
  sedentary_game = "ukb-b-4779",      # Plays computer games (n=462,433)
  # 备选（GWAS Catalog，需 tools/extract_iv_from_catalog.py 提取）
  # sedentary_cat = "GCST010084",     # 休闲久坐（看电视）n=408,815
  # screen_time   = "GCST90104339",   # 休闲屏幕时间 n=526,725

  # ---- 结局：银屑病 ----
  # 主结局见下方 FINNGEN 配置（R12 本地文件，12,760 例）
  # 以下为 OpenGWAS 上可即时调用的旧版 FinnGen（4,510 例），用于主流程与敏感性分析
  psoriasis      = "finn-b-L12_PSORIASIS",       # ncase=4,510 / ncontrol=212,242
  psoriasis_vulg = "finn-b-L12_PSORI_VULG",      # ncase=2,802
  psoriasis_arth = "finn-b-M13_PSORIARTH",       # ncase=1,553
  psoriasis_nas  = "finn-b-L12_PSORI_NAS",       # ncase=754

  # ---- 中介变量 ----
  bmi  = "ukb-b-19953",               # Body mass index (n=461,460)
  crp  = "ieu-b-35",                  # C-Reactive protein level (n=204,402)
  il6  = NULL,                        # 未在 OpenGWAS 找到合适 IL-6（可选，缺失即跳过）

  # ---- 参数 ----
  p_threshold = 5e-8,
  clump_r2    = 0.001,
  clump_kb    = 10000,
  f_min       = 10
)

## ★★ 方法学优势：暴露来自 UK Biobank / GWAS Catalog（英国），结局来自 FinnGen（芬兰），
##    人群完全不重叠 → 零样本重叠偏倚。请在 Methods 中明确写出。

## ---------- 8b. FinnGen R12 主结局（可选，功效更强）------------------------
# 实测（2026-10-03）：下载路径必须带 /release/ 子目录，否则 404
# 主结局 finngen_R12_L12_PSORIASIS：12,760 例 / 482,181 对照（为旧版 finn-b-* 的 2.8 倍）
FINNGEN <- list(
  use_local = FALSE,   # ★ 改为 TRUE 即用 R12 本地文件作主结局（需先跑 tools/fetch_finngen.py）
  dir       = file.path(PROJ_DIR, "data", "finngen"),
  base_url  = "https://storage.googleapis.com/finngen-public-data-r12/summary_stats/release/",
  endpoints = c(
    psoriasis      = "finngen_R12_L12_PSORIASIS",     # 12,760 / 482,181
    psoriasis_vulg = "finngen_R12_L12_PSORI_VULG",    # 7,912
    psoriasis_arth = "finngen_R12_M13_PSORIARTH",     # 4,290 / 315,115
    psoriasis_nas  = "finngen_R12_L12_PSORI_NAS"      # 2,452
  )
)

## ---------- 9. 银屑病项目专用配置（NHANES 观察臂）--------------------------
# ★ 实测（CDC 官方代码本逐周期核对）：
#   MCQ070 仅存在于 2009-2010 / 2011-2012 / 2013-2014
#   病例数 F=191, G=167, H=162 → 合计 520 例 / 19,527 人（患病率 2.66%）
#   变量名已并入上方 VARMAP（psoriasis_ever / psoriasis_degree / arthritis_type）
PSO_EXPECTED_CASES <- 520
PSO_ARTHRITIS_PSA_CODE <- 3L     # MCQ195 取值 3 = Psoriatic arthritis

# 自报银屑病的确认用药关键词（RXQ_RX 的 RXDDRUG 列，小写匹配，用于敏感性分析）
PSO_MED_KEYWORDS <- c(
  "methotrexate", "cyclosporine", "acitretin", "etretinate",
  "adalimumab", "etanercept", "infliximab", "ustekinumab",
  "secukinumab", "ixekizumab", "brodalumab", "guselkumab",
  "risankizumab", "tildrakizumab", "certolizumab", "apremilast",
  "deucravacitinib", "clobetasol", "calcipotriene", "betamethasone"
)

# ★ 统计功效硬约束（EPV 原则：每个估计参数至少 10 个事件）
#   520 例病例 → 参数上限 = 520/10 = 52；本项目主模型参数 = 15（含因子哑变量）
#   → EPV ≈ 34.7，满足要求。脚本 02/03 会实测并校验。
PSO_MAX_PARAMS <- 52
# 主模型参数数（用于 EPV 预校验）
# ★ 2026-10-03 由 15 改为 14：移除 total cholesterol（chol 缺失 9.4% 且不在排除条件内，
#   会导致「报告 n ≠ 模型 n」；且血脂不是 PA/久坐→银屑病 的合理混杂因素）。
#   参数计数：age1 + female1 + race4 + edu2 + pir1 + smoke2 + alc1 + htn1 + dm1 = 14
PSO_MAIN_PARAMS <- 14

## ---------- 10. 绘图风格 ----------------------------------------------------
FIG_DPI   <- 300
FIG_WIDTH <- 8
FIG_HEIGHT<- 6

## ---------- 11. 随机种子 ----------------------------------------------------
set.seed(20261003)
