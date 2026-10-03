Sys.setlocale("LC_CTYPE", "en_US.UTF-8")
source("R/config.R")

out <- file("R/_smoke_report.txt", open = "wt", encoding = "UTF-8")
sink(out, split = TRUE)

## 纯 base R，不依赖任何第三方包
coalesce0 <- function(x, y) ifelse(is.na(x), y, x)

pass <- 0; fail <- 0
chk <- function(cond, label, detail = "") {
  if (isTRUE(cond)) { pass <<- pass + 1; cat(sprintf("[PASS] %s\n", label)) }
  else { fail <<- fail + 1; cat(sprintf("[FAIL] %s  %s\n", label, detail)) }
}
near <- function(a, b, tol = 1e-2) isTRUE(all.equal(a, b, tolerance = tol))

cat("=== 冒烟测试 (base R) ", format(Sys.time()), " ===\n\n")

## ---- 1. FLI ---------------------------------------------------------------
compute_fli <- function(tg, bmi, ggt, wc) {
  y <- 0.953*log(tg) + 0.139*bmi + 0.718*log(ggt) + 0.053*wc - 15.745
  exp(y)/(1+exp(y))*100
}
f1 <- compute_fli(150, 30, 50, 100)
chk(f1 > 60 && f1 <= 100, "FLI 高危例 (>60)", sprintf("FLI=%.2f", f1))
f2 <- compute_fli(80, 21, 18, 75)
chk(f2 < 30, "FLI 低危例 (<30)", sprintf("FLI=%.2f", f2))
fv <- compute_fli(c(50,150,400), 25, c(15,50,120), 85)
chk(all(is.finite(fv)) && all(fv >= 0) && all(fv <= 100), "FLI 取值范围 [0,100]",
    paste(round(fv,1), collapse=","))
chk(is.na(suppressWarnings(compute_fli(-1, 25, 50, 85))), "FLI 对非法 TG 返回 NA")
chk(f1 > f2, "FLI 高危 > 低危（单调方向正确）")

## ---- 2. MET-min/week ------------------------------------------------------
calc_met <- function(vig_min, vig_d, mod_min, mod_d) 8*vig_min*vig_d + 4*mod_min*mod_d
chk(near(calc_met(30, 3, 30, 5), 8*90 + 4*150), "MET-min/wk 计算", calc_met(30,3,30,5))
grp <- cut(c(0, 300, 1500, 5000), breaks = c(-1,0,600,3000,Inf),
           labels = c("inactive","low","moderate","high"))
chk(as.character(grp[1])=="inactive" && as.character(grp[2])=="low" &&
    as.character(grp[3])=="moderate" && as.character(grp[4])=="high",
    "PA 分组切点全对", paste(as.character(grp), collapse=","))

## ---- 3. HSI ---------------------------------------------------------------
calc_hsi <- function(alt, ast, bmi, female, dm) 8*(alt/ast) + bmi + 2*female + 2*dm
h <- calc_hsi(60, 30, 32, 1, 1)
chk(near(h, 52), "HSI 计算 (=52)", sprintf("HSI=%.2f", h))
chk(h > HSI_CUT, "HSI 判为脂肪肝")

## ---- 4. eGFR (CKD-EPI 2021) ------------------------------------------------
calc_egfr <- function(scr, age, female) {
  k <- ifelse(female==1, 0.7, 0.9); a <- ifelse(female==1, -0.241, -0.302)
  142 * pmin(scr/k,1)^a * pmax(scr/k,1)^(-1.200) * 0.9938^age * ifelse(female==1,1.012,1)
}
e1 <- calc_egfr(1.0, 50, 0); e2 <- calc_egfr(1.0, 50, 1)
chk(abs(e1-92) < 2, "eGFR 男50y Scr1.0 ≈ 92（查表值）", sprintf("%.1f", e1))
chk(abs(e2-69) < 2, "eGFR 女50y Scr1.0 ≈ 69（查表值）", sprintf("%.1f", e2))
chk(e1 > e2, "eGFR 同 Scr 下 男 > 女（CKD-EPI 正确行为）", sprintf("F=%.1f M=%.1f", e2, e1))
chk(calc_egfr(3.0, 70, 0) < 30, "eGFR 重度下降识别", sprintf("%.1f", calc_egfr(3.0,70,0)))

## ---- 5. 缺失编码清洗 -------------------------------------------------------
clean_num <- function(x, codes = c(7,9,77,99,777,999,7777,9999,5555,6666)) {
  x[x %in% codes] <- NA; x
}
chk(identical(clean_num(c(1,7,3,99,20,7777)), c(1,NA,3,NA,20,NA)),
    "NHANES 缺失编码清洗", paste(clean_num(c(1,7,3,99,20,7777)), collapse=","))

## ---- 6. 饮酒 ---------------------------------------------------------------
alc <- function(alc12m, amt) ifelse(alc12m == 1, coalesce0(amt,0)*14, 0)
chk(near(alc(1,2), 28), "饮酒 g/d 换算", alc(1,2))
chk(alc(2,5) == 0, "不饮酒者为 0")

## ---- 7. 吸烟分类 -----------------------------------------------------------
smoke_fun <- function(s100, snow) {
  ifelse(s100==1 & snow %in% c(1,2), "current",
  ifelse(s100==1 & snow==3, "former",
  ifelse(s100==2, "never", NA)))
}
chk(smoke_fun(1,1)=="current" && smoke_fun(1,3)=="former" &&
    smoke_fun(2,NA)=="never" && is.na(smoke_fun(NA,NA)), "吸烟三分类")

## ---- 8. pick() -------------------------------------------------------------
pick <- function(df, varname, n) {
  if (is.null(df) || is.null(varname) || !(varname %in% names(df))) return(rep(NA, n))
  df[[varname]]
}
chk(all(is.na(pick(data.frame(a=1:3), "ZZZ", 3))), "pick() 缺列返回 NA")
chk(identical(pick(data.frame(a=1:3), "a", 3), 1:3), "pick() 正常取列")

## ---- 9. flow 记录函数 ------------------------------------------------------
flow <- data.frame(step="0", n=100)
step <- function(d, label) { flow <<- rbind(flow, data.frame(step=label, n=nrow(d))); d }
tmp <- step(data.frame(x=1:100)[1:50, , drop=FALSE], "1. filter")
chk(nrow(flow)==2 && flow$n[2]==50, "flow 记录函数", paste(flow$n, collapse=","))

## ---- 10. 配置完整性 --------------------------------------------------------
need <- c("age","sex","bmi","waist","tg","ggt","alt","ast","crp","wt_2yr",
          "psu","strata","acc_day_mims","acc_valid_min")
chk(all(need %in% names(VARMAP)), "VARMAP 关键变量齐全",
    paste(setdiff(need, names(VARMAP)), collapse=","))
chk(length(NHANES_CYCLES) == length(NHANES_YEARS), "周期与年份一一对应")
chk(identical(PAM_CYCLES, c("G","H")), "加速度计周期正确 (2011-2014)")

## ---- 11. 银屑病项目配置（2026-10-03 改造后）-------------------------------
chk(identical(NHANES_CYCLES, c("F","G","H")), "观察周期 = 2009-2014 (F/G/H)",
    paste(NHANES_CYCLES, collapse=","))
chk(identical(NHANES_YEARS, c("2009-2010","2011-2012","2013-2014")), "年份标签正确")
chk(identical(PAM_CYCLES, c("G","H")), "加速度计周期正确 (G/H = 2011-2014)")
chk(all(c("psoriasis_ever","psoriasis_degree","arthritis_type") %in% names(VARMAP)),
    "VARMAP 含银屑病变量")
chk(VARMAP$psoriasis_ever   == "MCQ070", "主结局变量 = MCQ070")
chk(VARMAP$psoriasis_degree == "MCQ075", "严重度变量 = MCQ075")
chk(VARMAP$arthritis_type   == "MCQ195", "关节炎类型变量 = MCQ195")
chk(PSO_ARTHRITIS_PSA_CODE == 3L, "银屑病关节炎编码 = 3")

# 病例数算术校验（实测值 F=191, G=167, H=162）
cases <- c(F = 191, G = 167, H = 162)
chk(sum(cases) == PSO_EXPECTED_CASES, "病例数合计 = 520",
    sprintf("实测 %d vs 配置 %d", sum(cases), PSO_EXPECTED_CASES))
tot <- 6889 + 6174 + 6464
chk(abs(sum(cases)/tot*100 - 2.66) < 0.01, "合并患病率 ≈ 2.66%",
    sprintf("%.2f%%", sum(cases)/tot*100))

# EPV 校验：520 例 / 14 参数 = 37.1 ≥ 10（2026-10-03 移除 chol 后由 15 改为 14）
epv <- PSO_EXPECTED_CASES / PSO_MAIN_PARAMS
chk(epv >= 10, "EPV 满足 (≥10)", sprintf("EPV=%.1f", epv))
chk(PSO_MAIN_PARAMS <= PSO_MAX_PARAMS, "主模型参数未超上限")

# 加速度计臂功效校验：应明确不足（<200 例）
acc_cases <- cases["G"] + cases["H"]
chk(acc_cases == 329 && acc_cases/3 < 200, "加速度计臂病例不足（须降级敏感性分析）",
    sprintf("两周期 %d 例，PAM 子样本估计 ~%d 例", acc_cases, round(acc_cases/3)))

# MR ID 完整性（2026-10-03 用 OpenGWAS API 实测核对后的口径）
need_mr <- c("pa_mvpa","pa_accel","pa_walk_dur","pa_strenuous",
             "sedentary_tv","psoriasis","psoriasis_vulg","psoriasis_arth",
             "psoriasis_nas","bmi","crp")
chk(all(need_mr %in% names(MR)), "MR 配置项齐全",
    paste(setdiff(need_mr, names(MR)), collapse=","))
chk(all(nzchar(unlist(MR[need_mr]))), "所有必需 ID 非空")

pso_ids <- unlist(MR[c("psoriasis","psoriasis_vulg","psoriasis_arth","psoriasis_nas")])
chk(all(grepl("^finn-b-", pso_ids)), "银屑病结局 ID 为 OpenGWAS FinnGen 命名",
    paste(pso_ids, collapse=","))
chk(grepl("^ebi-a-GCST", MR$pa_mvpa), "MVPA 主暴露来自 GWAS Catalog 导入")
chk(grepl("^ukb-b-", MR$sedentary_tv), "久坐主暴露为 UKB TV watching")

chk(length(PSO_MED_KEYWORDS) >= 15, "银屑病确认用药关键词足够")

# FinnGen R12 配置
chk(is.logical(FINNGEN$use_local), "FINNGEN$use_local 为逻辑值")
chk(grepl("/release/$", FINNGEN$base_url), "★ FinnGen URL 含 /release/（缺了会 404）")
chk(all(grepl("^finngen_R12_", FINNGEN$endpoints)), "FinnGen R12 endpoint 命名正确")
chk(length(FINNGEN$endpoints) == 4, "FinnGen R12 配置了 4 个 endpoint")

# 工具脚本存在性
for (t in c("tools/check_gwas_ids.py", "tools/probe_ids.py",
            "tools/fetch_finngen.py", "tools/check_token.py")) {
  chk(file.exists(t), paste0("工具存在：", basename(t)))
}

cat(sprintf("\n=== 结果：PASS %d / FAIL %d ===\n", pass, fail))
sink(); close(out)
cat(sprintf("PASS %d, FAIL %d\n", pass, fail))
