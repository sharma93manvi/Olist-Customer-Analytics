# Olist Customer Analytics

End-to-end retention analytics on **93,349 customers** and **100K+ orders** from Olist, Brazil's largest e-commerce marketplace.

## The Problem

Olist's repeat purchase rate is just **~3%** — 97% of customers buy once and never return, leaving significant lifetime value untapped.

## What We Built

| Component | Detail |
|-----------|--------|
| **RFM Segmentation** | 5 customer segments based on recency, frequency, monetary value, and predicted repeat probability |
| **CLV Model** | Granular customer lifetime value using model-based P(repeat) instead of flat averages |
| **Repeat Buyer Classifier** | Logistic regression, AUC **0.743** on holdout — identifies 888 high-potential dormant buyers |
| **Targeting P&L** | BRL 15 intervention → 158 expected conversions → **R$ 8,453 net profit** per cycle |
| **Revenue Scenarios** | 3%→5% repeat = R$ 542K incremental; 3%→6% = R$ 814K incremental |
| **Experiment Design** | Randomized controlled trial (3,014 customers) to validate causal lift before scaling |
| **Interactive Dashboard** | React + Recharts — KPIs, segmentation, model performance, P&L, experiment comparison |

## Key Findings

- **Vouchers are the #1 lever** — customers who used vouchers are 3.8× more likely to return (OR 3.81)
- **888 High-Potential Dormant Buyers** represent just 1% of the base but hold R$ 326 avg CLV — 96× higher than the low-potential segment
- **Delivery delays hurt** — late deliveries and high freight reduce repeat probability
- **ROI-positive at conservative estimates** — 63% return on R$ 13,320 investment even with 17.8% conversion rate


## Repository Structure

```
├── Group3_Olist_Master_Analysis.R    # Full R pipeline (Sections 1–6)
├── Group3_End_to_End_Walkthrough_and_Results.md
├── olist-dashboard/                  # React + Recharts interactive dashboard
│   ├── src/App.jsx                   # Dashboard components & hardcoded data
│   ├── src/App.css                   # Styling
│   └── package.json
├── output/
│   ├── plots/                        # EDA visualizations (6 PNGs)
│   └── tables/                       # Analysis CSVs (segmentation, P&L, CLV, etc.)
└── README.md
```

## Running the R Pipeline

```r
# Set working directory to project root, then:
source("Group3_Olist_Master_Analysis.R")
```

Requires: `tidyverse`, `lubridate`, `scales`, `broom`, `pROC`. Outputs go to `output/tables/` and `output/plots/`.

## Running the Dashboard

```bash
cd olist-dashboard
npm install
npm run dev
```

Opens at `http://localhost:5173`. All data is hardcoded from CSV outputs — no file upload needed.

## Team

Group 3 — BAMA 520, Customer Analytics

## Data Source

[Olist Brazilian E-Commerce Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle)
