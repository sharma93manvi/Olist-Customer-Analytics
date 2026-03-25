# Group 3 — Olist Customer Analytics: End-to-End Walkthrough & Final Results

**Source script:** `Group3_Olist_Master_Analysis.R`  
**Client:** Olist (Brazilian e-commerce marketplace; use this name on Slide 1, not “the platform”).  
**Last run:** March 24, 2026 — full `Rscript` execution (see §2). §4 numeric outputs re-checked from CSVs; unchanged from prior run.

---

## 1. What the master file includes vs. what was dropped (professor feedback)

### Included (full analytical chain)

| Step | Section | Purpose |
|------|---------|---------|
| 1 | Data + RFM | Load/clean Olist inputs **or** pre-cleaned `orders_full` + `rfm_table` (supports `Clean Dataset csv/`). |
| 1B | EDA plots | Milestone 2 visuals (`milestone2_EDA.R`): repeat vs one-time, spend, delay, recency, reviews, repeat vs one-time spend → `plots/viz1_*.png` … `viz6_*.png` (toggle `RUN_MILESTONE2_EDA`). |
| 2 | Baseline CLV | `CLV = P(repeat) × AOV × frequency` with **flat** ~3% for one-time buyers (baseline only; needed so the classifier can join `clv_tier` / `clv_score` as in the original pipeline). |
| 3 | Drivers + model | First-order delay, experience signals, **logistic regression** repeat classifier, **AUC**, feature importance, **P(repeat)** scores. **Recency and frequency are excluded** from predictors (no leakage). |
| 4 | CLV v2 + P&L | Replaces flat 3% with **model-based P(repeat)** for one-time buyers; **revenue scenarios**; **targeting P&L** (BRL 15 = BRL 10 voucher + BRL 5 delivery). |
| 5 | Validation design | **Randomized experiment** sketch + `power.prop.test` + scale-up vs. experiment economics → `experiment_summary.csv`. |
| 6 | Segmentation | Matrix with **High-Potential Dormant Buyers** (one-time, P(repeat) ≥ 10%) and interventions. |

### Intentionally not in the master script (Milestone 3 scope discipline)

- **Regional CLV mapping, cohort analysis, seller-level deep dives** — called out in professor feedback as **deprioritized** unless they directly support the single costed recommendation.
- **Archive scripts** `DD&ES.r` and `RepeatvsOnetimeClassifier.r` — superseded by the unified classifier in Section 3.

### How feedback is reflected in code

- **Dollar Sign Rule:** Section 4 outputs `targeting_pl_table.csv` (threshold, cost, expected conversions, revenue, net profit).
- **Granular CLV:** Section 4 uses **predicted P(repeat)** per customer for one-time buyers.
- **Causality:** Section 5 proposes an RCT before scaling voucher-led retention.
- **Naming:** Segmentation uses **“High-Potential Dormant Buyers”** for the primary target segment.

---

## 2. Console output (last full run)

Command:

```bash
cd "/path/to/R files"
Rscript Group3_Olist_Master_Analysis.R
```

**Exit code:** 0  

**Log (abridged; package load warnings omitted):**

```
=== Section 1: Loading pre-cleaned orders + RFM (RDS or CSV) ===
=== Section 1B: EDA plots saved to .../R files/plots ===

=== Group 3 master script finished. Key outputs in OUTPUT_DIR ===
AUC (holdout): 0.743
Targeting P&L saved: .../R files/targeting_pl_table.csv
Experiment summary: .../R files/experiment_summary.csv
Segmentation matrix: .../R files/segmentation_matrix_final.csv
Milestone 2 EDA plots: .../R files/plots (viz1_repeat_vs_onetime.png … viz6_monetary_repeat_vs_onetime.png)
```

**Note:** If `olist_orders_dataset.csv` is present in `RAW_DATA_DIR`, Section 1 runs **full cleaning** from raw files and prints additional row-count diagnostics.

---

## 3. End-to-end pipeline (what happens in order)

1. **Section 1 — Data & RFM**  
   - Either rebuild from raw Olist CSVs, or load `orders_full` + `rfm_table` from RDS/CSV (including `Clean Dataset csv/`).  
   - Customer grain: `customer_unique_id`. **Repeat buyer** = `frequency ≥ 2`. **Monetary** = sum of item price (freight separate).

1B. **Section 1B — EDA (Milestone 2)**  
   - Writes six PNGs under `plots/` (repeat-rate bar chart, monetary histogram, delivery delay, recency, review buckets, repeat vs one-time spend boxplot). Controlled by `RUN_MILESTONE2_EDA`.

2. **Section 2 — Baseline CLV**  
   - One-time buyers get **global** P(repeat) ≈ 3%; repeat buyers get P(repeat) = 1.  
   - Writes `clv_table.csv` / `clv_table.rds` and first-pass `revenue_impact_table.csv`.

3. **Section 3 — Experience + classifier**  
   - First-order delivery delay, delay bands, experience summaries.  
   - Train/test split 70/30, seed **520**. Logistic model; **AUC** on holdout.  
   - Writes `delay_threshold_table.csv`, `experience_summary.csv`, `feature_importance_ranking.csv`, `customer_p_repeat_scores.csv`.

4. **Section 4 — CLV v2 + scenarios + targeting**  
   - Merges **model P(repeat)** into CLV for one-time buyers.  
   - Overwrites `revenue_impact_table.csv` with scenario math tied to current base rate.  
   - **Targeting rule:** one-time buyers with **P(repeat) ≥ 10%**; cost **BRL 15** per contacted customer.  
   - Writes `clv_table_v2.csv`, `targeting_pl_table.csv`.

5. **Section 5 — Experiment**  
   - Power analysis for detecting a **+2 pp** lift in repeat rate; compares **pilot economics** (often negative) vs **scale-up** on the high-P(repeat) segment.  
   - Writes `experiment_summary.csv`.

6. **Section 6 — Segmentation matrix**  
   - Writes `segmentation_matrix_final.csv`.

---

## 4. Final results (key tables from this run)

### 4.1 Model performance

| Metric | Value |
|--------|--------|
| Holdout AUC | **0.743** |

### 4.2 Feature importance (logistic regression; ranked by \|coefficient\|)

Interpret **payment method** coefficients with care: reference-category effects can inflate credit card / boleto magnitudes. For slide narrative, emphasize **voucher**, **installments**, **freight**, **delay**, **monetary** per your Milestone 2 writeup.

| Rank | Feature | Odds ratio | Direction |
|------|---------|------------|-----------|
| 1 | used_boleto | 97.86 | Increases P(repeat) |
| 2 | used_credit_card | 90.17 | Increases P(repeat) |
| 3 | **used_voucher** | **3.81** | Increases P(repeat) |
| 4 | avg_installments | 1.03 | Increases P(repeat) |
| 5 | avg_review_score | 1.02 | Not significant (p ≈ 0.33) |
| 6 | avg_freight | 0.99 | Decreases P(repeat) |
| 7 | first_delivery_delay_days | 0.99 | Decreases P(repeat) |
| 8 | monetary | 1.001 | Increases P(repeat) |

### 4.3 Revenue scenarios (platform-wide repeat-rate lift)

Assumes incremental buyers × average order value (all customers) × average repeat frequency among repeat buyers.

| Scenario | Incremental buyers | AOV (BRL) | Avg repeat frequency | Incremental revenue (BRL) |
|----------|-------------------:|----------:|---------------------:|--------------------------:|
| 3% → 5% | 1,866 | 137.51 | 2.11 | **542,532** |
| 3% → 6% | 2,800 | 137.51 | 2.11 | **813,876** |

### 4.4 Targeting P&L (costed recommendation — “High-Potential Dormant Buyers”)

**Rule:** One-time buyers with **P(repeat) ≥ 10%**.  
**Assumed intervention cost:** **BRL 15** per customer (BRL 10 voucher + BRL 5 delivery).  
**Expected revenue (script):** Σ P(repeat) × average order value (all customers), interpreted as expected value of **one incremental order** from the campaign perspective.

| Metric | Value |
|--------|------:|
| Customers targeted | **888** |
| Total intervention cost (BRL) | **13,320** |
| Expected conversions | **158** |
| Expected revenue (BRL) | **21,773** |
| **Net profit (BRL)** | **8,453** |

### 4.5 Randomized experiment vs. scale-up (`experiment_summary.csv`)

| Phase | Metric | Value |
|-------|--------|-------|
| Experiment | Sample size (total) | 3,014 customers |
| Experiment | Cost (BRL 15/customer) | BRL 22,605 |
| Experiment | Expected net profit | BRL -18,461 |
| Scale-up | Target segment | 888 customers |
| Scale-up | Cost (BRL 15/customer) | BRL 13,320 |
| Scale-up | Expected conversions | 158 |
| Scale-up | Net profit (per cycle) | BRL 8,453 |

*Interpretation:* The **pilot** is framed as a **learning investment** (negative expected profit under conservative assumptions); **scale-up** economics apply to the **scored** high-P(repeat) segment **after** causal validation.

### 4.6 Segmentation matrix (summary)

| Segment | Size (N) | Avg. granular CLV (BRL) | Recommended intervention |
|---------|----------|-------------------------|---------------------------|
| High-Potential Dormant Buyers | 888 | 326.18 | Direct re-engagement: BRL 10 voucher + delivery subsidy (as in P&L) |
| Loyalty Champions | 2,801 | 260.05 | VIP retention |
| Medium-Potential | 3,154 | 29.27 | Soft nurture (installments) |
| Low-Potential | 76,806 | 3.40 | Passive reach |
| Low-Value Passives | 9,700 | 1.57 | Do not target |

**Total customers in matrix:** 93,349 (= 888 + 2,801 + 3,154 + 76,806 + 9,700).

### 4.7 EDA plots (Section 1B — this run)

Saved under the project folder `plots/`:

| File | Content |
|------|---------|
| `viz1_repeat_vs_onetime.png` | Repeat vs one-time customer counts |
| `viz2_monetary_distribution.png` | Total spend per customer (log scale) |
| `viz3_delivery_delay.png` | Order-level delivery delay vs on-time / late |
| `viz4_recency_distribution.png` | Days since last purchase |
| `viz5_review_scores.png` | Average review score buckets |
| `viz6_monetary_repeat_vs_onetime.png` | Total spend: repeat vs one-time (log boxplot) |

---

## 5. Output files written by the master script

| File | Description |
|------|-------------|
| `clv_table.csv`, `clv_table.rds` | Baseline CLV |
| `revenue_impact_table.csv` | Scenario revenue (overwritten in Sec 4 with v2-aligned scenarios) |
| `delay_threshold_table.csv` | Repeat rate by first-order delay band |
| `experience_summary.csv` | Experience metrics by buyer type |
| `feature_importance_ranking.csv` | Model coefficients / odds ratios |
| `customer_p_repeat_scores.csv` | Customer-level P(repeat) and bands |
| `clv_table_v2.csv`, `clv_table_v2.rds` | CLV with model P(repeat) |
| `targeting_pl_table.csv` | **Slide 8–style P&L** |
| `experiment_summary.csv` | **Slide 9–style validation / economics** |
| `segmentation_matrix_final.csv` | **Segmentation matrix** |
| `plots/viz1_repeat_vs_onetime.png` … `plots/viz6_monetary_repeat_vs_onetime.png` | **EDA figures** (Section 1B; skip if `RUN_MILESTONE2_EDA <- FALSE`) |

When `RUN_FULL_CLEANING` is TRUE, additional cleaned tables (`cleaned_orders.csv`, `orders_full.csv`, etc.) are also written.

---

## 6. One-line story for the pitch

Olist’s repeat rate is ~3%; CLV and scenarios show large revenue upside if repeat moves to 5–6%; a leakage-aware model (AUC **0.743**) surfaces **888** **High-Potential Dormant Buyers** at P(repeat) ≥ 10%; a **BRL 15** intervention yields about **BRL 8.5K** expected net profit on this segment **before** scaling—**after** a randomized voucher test to confirm causality.

---

*This document is generated to match `Group3_Olist_Master_Analysis.R` and the CSV outputs in the same folder. Re-run the script after any data or code change and refresh the numbers in §4.*
