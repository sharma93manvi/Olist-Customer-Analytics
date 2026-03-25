# ==============================================================================
# BAMA 520 — Group 3 | Olist (Brazilian E-Commerce) — MASTER ANALYSIS SCRIPT
# ==============================================================================
#
# Purpose: One reproducible file that runs the full pipeline previously split
# across folders 1–7 + milestone2_EDA.R:
#   (1) Data cleaning + RFM
#   (1B) Milestone 2 EDA plots (repeat, spend, delay, recency, reviews, spend by type)
#   (2) CLV (baseline flat P(repeat) for one-time buyers)
#   (3) Delivery / experience exploration + repeat-buyer logistic model + scores
#   (4) CLV v2 using model P(repeat) + revenue scenarios + targeting P&L
#   (5) Randomized experiment design + power analysis (causal validation)
#   (6) Segmentation matrix (presentation-ready table)
#
# Client: Olist (name explicitly in slides; avoid generic “the platform”).
#
# -----------------------------------------------------------------------------
# Professor feedback (Milestone 2 → 3) — design principles encoded here
# -----------------------------------------------------------------------------
# • Stop expanding scope: deprioritize regional mapping, cohort analysis,
#   seller-level deep dives unless they directly support the one recommendation.
# • “Dollar Sign Rule”: one costed recommendation — targeting rule + cost +
#   expected conversions + net profit (Targeting P&L section).
# • Replace flat CLV P(repeat)=3% for all one-time buyers with each customer’s
#   predicted P(repeat) from the classifier (CLV v2 section).
# • Address causality: voucher may correlate with engagement; propose an RCT
#   before scaling (Experiment section).
# • Primary segment label: “High-Potential Dormant Buyers” = one-time buyers
#   with above-threshold predicted P(repeat) (e.g. ≥ 10%).
#
# Not merged (superseded / alternate drafts):
# • Archive: DD&ES.r, RepeatvsOnetimeClassifier.r — older paths and logic;
#   current model + tables follow Binary Classification_Full.R.
#
# ==============================================================================
# CONFIGURATION — edit before running
# ==============================================================================

# Project root (where the script lives and input data resides).
PROJECT_DIR <- getwd()

# Structured output directories — created automatically below.
OUTPUT_DATA_DIR   <- file.path(PROJECT_DIR, "output", "data")    # cleaned data (Section 1)
OUTPUT_TABLES_DIR <- file.path(PROJECT_DIR, "output", "tables")  # analysis CSVs / RDS
OUTPUT_PLOTS_DIR  <- file.path(PROJECT_DIR, "output", "plots")   # EDA & model plots

dir.create(OUTPUT_DATA_DIR,   showWarnings = FALSE, recursive = TRUE)
dir.create(OUTPUT_TABLES_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(OUTPUT_PLOTS_DIR,  showWarnings = FALSE, recursive = TRUE)

# Folder containing raw Olist CSV files (olist_orders_dataset.csv, etc.).
# If identical to PROJECT_DIR, leave as-is. If raw files live elsewhere, set path.
RAW_DATA_DIR <- PROJECT_DIR

# If TRUE and raw `olist_orders_dataset.csv` exists under RAW_DATA_DIR, Section 1
# runs full cleaning. If FALSE, Section 1 loads existing `orders_full.rds` and
# `rfm_table.rds` from OUTPUT_DIR (skips raw import).
RUN_FULL_CLEANING <- file.exists(file.path(RAW_DATA_DIR, "olist_orders_dataset.csv"))

# Save ggplot objects to PNG (optional; plots always print when run interactively)
SAVE_PLOT_FILES <- FALSE

# Milestone 2 descriptive charts (milestone2_EDA.R) → OUTPUT_DIR/plots/viz*.png
RUN_MILESTONE2_EDA <- TRUE

# Random seed (train/test split + any stochastic steps)
set.seed(520)

# ==============================================================================
# Libraries
# ==============================================================================

library(tidyverse)
library(lubridate)
library(purrr)
library(scales)
library(broom)
library(pROC)

select <- dplyr::select  # avoid clashes with e.g. MASS::select

# ==============================================================================
# Helpers
# ==============================================================================

data_path   <- function(...) file.path(OUTPUT_DATA_DIR,   ...)
tables_path <- function(...) file.path(OUTPUT_TABLES_DIR, ...)
plots_path  <- function(...) file.path(OUTPUT_PLOTS_DIR,  ...)
raw_path    <- function(...) file.path(RAW_DATA_DIR, ...)

# ==============================================================================
# SECTION 1 — Data loading, cleaning, RFM (original: 1. Data Cleaning/milestone2.R)
# ==============================================================================

if (RUN_FULL_CLEANING) {
  message("=== Section 1: Full cleaning from raw Olist CSVs ===")

  orders               <- read_csv(raw_path("olist_orders_dataset.csv"),                show_col_types = FALSE)
  customers            <- read_csv(raw_path("olist_customers_dataset.csv"),              show_col_types = FALSE)
  order_items          <- read_csv(raw_path("olist_order_items_dataset.csv"),            show_col_types = FALSE)
  payments             <- read_csv(raw_path("olist_order_payments_dataset.csv"),         show_col_types = FALSE)
  reviews              <- read_csv(raw_path("olist_order_reviews_dataset.csv"),          show_col_types = FALSE)
  products             <- read_csv(raw_path("olist_products_dataset.csv"),               show_col_types = FALSE)
  geo                  <- read_csv(raw_path("olist_geolocation_dataset.csv"),            show_col_types = FALSE)
  category_translation <- read_csv(raw_path("product_category_name_translation.csv"),   show_col_types = FALSE)

  cat("========== RAW ROW COUNTS ==========\n")
  cat("  orders:", format(nrow(orders), big.mark = ","), "\n\n")

  products_clean <- products %>%
    left_join(category_translation, by = "product_category_name") %>%
    mutate(
      product_category_name_english = if_else(
        is.na(product_category_name_english),
        "unknown",
        product_category_name_english
      )
    )

  geo_clean <- geo %>%
    group_by(geolocation_zip_code_prefix) %>%
    summarise(
      geolocation_lat   = median(geolocation_lat),
      geolocation_lng   = median(geolocation_lng),
      geolocation_city  = first(geolocation_city),
      geolocation_state = first(geolocation_state),
      .groups = "drop"
    )

  orders_clean <- orders %>%
    mutate(
      order_purchase_timestamp      = ymd_hms(order_purchase_timestamp),
      order_delivered_customer_date = ymd_hms(order_delivered_customer_date),
      order_estimated_delivery_date = ymd(order_estimated_delivery_date)
    ) %>%
    filter(order_status == "delivered") %>%
    filter(!is.na(order_delivered_customer_date)) %>%
    mutate(
      delivery_delay_days = as.numeric(
        difftime(order_delivered_customer_date, order_estimated_delivery_date, units = "days")
      ),
      delivered_late = if_else(delivery_delay_days > 0, 1, 0)
    )

  REFERENCE_DATE <- max(orders_clean$order_purchase_timestamp, na.rm = TRUE)

  reviews_clean <- reviews %>%
    arrange(order_id, desc(review_answer_timestamp)) %>%
    distinct(order_id, .keep_all = TRUE)

  order_items_agg <- order_items %>%
    group_by(order_id) %>%
    summarise(
      total_item_value = sum(price,         na.rm = TRUE),
      total_freight    = sum(freight_value, na.rm = TRUE),
      item_count       = n(),
      .groups = "drop"
    ) %>%
    mutate(order_total = total_item_value + total_freight)

  payments_agg <- payments %>%
    group_by(order_id) %>%
    summarise(
      total_payment_value  = sum(payment_value,        na.rm = TRUE),
      max_installments     = max(payment_installments),
      payment_method_count = n_distinct(payment_type),
      used_credit_card     = as.integer(any(payment_type == "credit_card")),
      used_boleto          = as.integer(any(payment_type == "boleto")),
      used_voucher         = as.integer(any(payment_type == "voucher")),
      .groups = "drop"
    )

  master <- orders_clean %>%
    left_join(customers, by = "customer_id") %>%
    left_join(order_items_agg, by = "order_id") %>%
    left_join(payments_agg, by = "order_id")

  orders_full <- master %>%
    left_join(reviews_clean %>% select(order_id, review_score), by = "order_id")

  write_csv(orders_clean,     data_path("cleaned_orders.csv"))
  write_csv(products_clean,   data_path("cleaned_products.csv"))
  write_csv(geo_clean,        data_path("cleaned_geo.csv"))
  write_csv(payments_agg,     data_path("cleaned_payments_agg.csv"))
  write_csv(order_items_agg,  data_path("cleaned_order_items_agg.csv"))
  write_csv(reviews_clean,    data_path("cleaned_reviews.csv"))
  write_csv(orders_full,      data_path("orders_full.csv"))
  saveRDS(orders_full,        data_path("orders_full.rds"))

  rfm_table <- orders_full %>%
    group_by(customer_unique_id) %>%
    summarise(
      recency_days     = as.numeric(difftime(REFERENCE_DATE, max(order_purchase_timestamp, na.rm = TRUE), units = "days")),
      frequency        = n_distinct(order_id),
      monetary         = sum(total_item_value, na.rm = TRUE),
      is_repeat_buyer  = as.integer(frequency >= 2),
      avg_order_value  = mean(total_item_value, na.rm = TRUE),
      first_purchase   = min(order_purchase_timestamp, na.rm = TRUE),
      last_purchase    = max(order_purchase_timestamp, na.rm = TRUE),
      avg_review_score    = mean(review_score,        na.rm = TRUE),
      avg_delivery_delay  = mean(delivery_delay_days, na.rm = TRUE),
      pct_late_orders     = mean(delivered_late,      na.rm = TRUE) * 100,
      avg_freight         = mean(total_freight,        na.rm = TRUE),
      avg_installments    = mean(max_installments,    na.rm = TRUE),
      used_credit_card    = as.integer(any(used_credit_card == 1)),
      used_boleto         = as.integer(any(used_boleto == 1)),
      used_voucher        = as.integer(any(used_voucher == 1)),
      customer_state   = first(customer_state),
      customer_city    = first(customer_city),
      .groups = "drop"
    ) %>%
    filter(is.finite(recency_days))

  write_csv(rfm_table, data_path("rfm_table.csv"))
  saveRDS(rfm_table,   data_path("rfm_table.rds"))

} else {
  message("=== Section 1: Loading pre-cleaned orders + RFM (RDS or CSV) ===")

  # Search order: output/data/ first, then project root for backwards compat
  rds_orders     <- data_path("orders_full.rds")
  csv_orders_out <- data_path("orders_full.csv")
  rds_orders_root <- file.path(PROJECT_DIR, "orders_full.rds")
  csv_orders_root <- file.path(PROJECT_DIR, "orders_full.csv")

  if (file.exists(rds_orders)) {
    orders_full <- readRDS(rds_orders)
  } else if (file.exists(csv_orders_out)) {
    orders_full <- read_csv(csv_orders_out, show_col_types = FALSE)
  } else if (file.exists(rds_orders_root)) {
    orders_full <- readRDS(rds_orders_root)
  } else if (file.exists(csv_orders_root)) {
    orders_full <- read_csv(csv_orders_root, show_col_types = FALSE)
  } else {
    stop(
      "Pre-cleaned data not found. Place `orders_full.rds` or `orders_full.csv` in output/data/ or project root,\n",
      "or set RUN_FULL_CLEANING with raw Olist CSVs in RAW_DATA_DIR."
    )
  }

  rds_rfm     <- data_path("rfm_table.rds")
  csv_rfm_out <- data_path("rfm_table.csv")
  rds_rfm_root <- file.path(PROJECT_DIR, "rfm_table.rds")
  csv_rfm_root <- file.path(PROJECT_DIR, "rfm_table.csv")

  if (file.exists(rds_rfm)) {
    rfm_table <- readRDS(rds_rfm)
  } else if (file.exists(csv_rfm_out)) {
    rfm_table <- read_csv(csv_rfm_out, show_col_types = FALSE)
  } else if (file.exists(rds_rfm_root)) {
    rfm_table <- readRDS(rds_rfm_root)
  } else if (file.exists(csv_rfm_root)) {
    rfm_table <- read_csv(csv_rfm_root, show_col_types = FALSE)
  } else {
    stop("Pre-cleaned `rfm_table` not found (.rds or .csv in output/data/ or project root).")
  }

  REFERENCE_DATE <- max(orders_full$order_purchase_timestamp, na.rm = TRUE)
}

# ==============================================================================
# SECTION 1B — Milestone 2 EDA visualizations (original: milestone2_EDA.R)
# ==============================================================================
# Slide-ready descriptive plots: core 3% repeat problem, spend heterogeneity,
# delivery delay, recency, review scores, repeat vs one-time spend.
# Set RUN_MILESTONE2_EDA <- FALSE to skip (e.g. batch runs where plots are not needed).
# ==============================================================================

if (RUN_MILESTONE2_EDA) {
  plot_dir <- OUTPUT_PLOTS_DIR

  n_customers <- nrow(rfm_table)
  ref_date_str <- tryCatch(
    format(as.Date(max(orders_full$order_purchase_timestamp, na.rm = TRUE)), "%Y-%m-%d"),
    error = function(e) "see orders_full"
  )

  # --- VIZ 1: Repeat vs one-time buyers ---
  p_eda1 <- rfm_table %>%
    count(is_repeat_buyer) %>%
    mutate(
      label     = if_else(is_repeat_buyer == 1, "Repeat buyers", "One-time buyers"),
      pct       = round(n / sum(n) * 100, 1),
      pct_label = paste0(pct, "%")
    ) %>%
    ggplot(aes(x = label, y = n, fill = label)) +
    geom_col(width = 0.5) +
    geom_text(aes(label = pct_label), vjust = -0.5, size = 5, fontface = "bold") +
    scale_fill_manual(values = c(
      "One-time buyers" = "#D85A30",
      "Repeat buyers"   = "#1D9E75"
    )) +
    scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.12))) +
    labs(
      title    = "97% of customers never return",
      subtitle = paste0(
        "Repeat purchase rate ≈ 3% across ",
        format(n_customers, big.mark = ","), " unique customers (Olist)"
      ),
      x = NULL, y = "Number of customers",
      caption = "Source: rfm_table — customer_unique_id level"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      legend.position      = "none",
      plot.title           = element_text(face = "bold", size = 14),
      plot.subtitle        = element_text(color = "gray50", size = 11),
      panel.grid.major.x   = element_blank()
    )
  ggsave(file.path(plot_dir, "viz1_repeat_vs_onetime.png"), p_eda1, width = 6, height = 5, dpi = 150)

  # --- VIZ 2: Monetary distribution (log) ---
  p_eda2 <- rfm_table %>%
    filter(monetary > 0) %>%
    ggplot(aes(x = monetary)) +
    geom_histogram(bins = 50, fill = "#378ADD", color = "white") +
    scale_x_log10(labels = scales::comma) +
    scale_y_continuous(labels = scales::comma) +
    labs(
      title    = "Wide spread in customer spend justifies segmentation",
      subtitle = "Total spend per customer (BRL, log scale) — monetary = price only",
      x = "Total spend (BRL, log scale)", y = "Number of customers",
      caption = "Source: rfm_table — monetary = sum(price) per customer_unique_id"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = 14), plot.subtitle = element_text(color = "gray50", size = 11))
  ggsave(file.path(plot_dir, "viz2_monetary_distribution.png"), p_eda2, width = 7, height = 5, dpi = 150)

  # --- VIZ 3: Delivery delay (order-level) ---
  if (all(c("delivery_delay_days", "delivered_late") %in% names(orders_full))) {
    p_eda3 <- orders_full %>%
      filter(
        !is.na(delivery_delay_days),
        delivery_delay_days > -60,
        delivery_delay_days < 100
      ) %>%
      mutate(delivered_late_f = factor(delivered_late, levels = c(0, 1), labels = c("On time or early", "Late"))) %>%
      ggplot(aes(x = delivery_delay_days, fill = delivered_late_f)) +
      geom_histogram(bins = 60, color = "white") +
      scale_fill_manual(values = c("On time or early" = "#1D9E75", "Late" = "#D85A30")) +
      scale_y_continuous(labels = scales::comma) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "gray40", linewidth = 0.8) +
      annotate("text", x = 1, y = Inf, label = "Late →", hjust = 0, vjust = 1.5, size = 3.5, color = "#D85A30") +
      annotate("text", x = -1, y = Inf, label = "← Early", hjust = 1, vjust = 1.5, size = 3.5, color = "#1D9E75") +
      labs(
        title    = "Most orders arrive early — but ~8% are late",
        subtitle = "Delivery delay in days (actual minus estimated delivery date)",
        x = "Delivery delay (days)", y = "Number of orders",
        fill = NULL,
        caption = "Source: orders_full — delivered orders"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        legend.position = "top",
        plot.title      = element_text(face = "bold", size = 14),
        plot.subtitle   = element_text(color = "gray50", size = 11)
      )
    ggsave(file.path(plot_dir, "viz3_delivery_delay.png"), p_eda3, width = 7, height = 5, dpi = 150)
  } else {
    message("EDA VIZ 3 skipped: orders_full missing delivery_delay_days / delivered_late.")
  }

  # --- VIZ 4: Recency ---
  p_eda4 <- rfm_table %>%
    ggplot(aes(x = recency_days)) +
    geom_histogram(bins = 50, fill = "#7F77DD", color = "white") +
    scale_y_continuous(labels = scales::comma) +
    geom_vline(xintercept = median(rfm_table$recency_days, na.rm = TRUE),
               linetype = "dashed", color = "gray40", linewidth = 0.8) +
    annotate(
      "text",
      x = median(rfm_table$recency_days, na.rm = TRUE) + 5, y = Inf,
      label = paste0("Median: ", round(median(rfm_table$recency_days, na.rm = TRUE)), " days"),
      hjust = 0, vjust = 1.5, size = 3.5, color = "gray40"
    ) +
    labs(
      title    = "Most customers have not purchased in over 6 months",
      subtitle = paste0("Days since last purchase (recency) across ", format(n_customers, big.mark = ","), " customers"),
      x = "Days since last purchase", y = "Number of customers",
      caption = paste0("Source: rfm_table — reference date: ", ref_date_str)
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = 14), plot.subtitle = element_text(color = "gray50", size = 11))
  ggsave(file.path(plot_dir, "viz4_recency_distribution.png"), p_eda4, width = 7, height = 5, dpi = 150)

  # --- VIZ 5: Review scores ---
  n_no_review <- sum(is.na(rfm_table$avg_review_score))
  p_eda5 <- rfm_table %>%
    filter(!is.na(avg_review_score)) %>%
    mutate(score_bucket = factor(floor(avg_review_score))) %>%
    count(score_bucket) %>%
    ggplot(aes(x = score_bucket, y = n, fill = score_bucket)) +
    geom_col(width = 0.6) +
    geom_text(aes(label = scales::comma(n)), vjust = -0.5, size = 3.5) +
    scale_fill_manual(values = c(
      "1" = "#E24B4A", "2" = "#EF9F27",
      "3" = "#888780", "4" = "#5DCAA5", "5" = "#1D9E75"
    )) +
    scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.12))) +
    labs(
      title    = "Customer satisfaction skews strongly positive",
      subtitle = "Average review score per customer (1 = worst, 5 = best)",
      x = "Review score", y = "Number of customers",
      caption = paste0(format(n_no_review, big.mark = ","), " customers excluded — no review on record")
    ) +
    theme_minimal(base_size = 12) +
    theme(
      legend.position      = "none",
      plot.title           = element_text(face = "bold", size = 14),
      plot.subtitle        = element_text(color = "gray50", size = 11),
      panel.grid.major.x   = element_blank()
    )
  ggsave(file.path(plot_dir, "viz5_review_scores.png"), p_eda5, width = 6, height = 5, dpi = 150)

  # --- VIZ 6: Monetary — repeat vs one-time (milestone2_EDA.R was incomplete; boxplot on log scale) ---
  p_eda6 <- rfm_table %>%
    filter(monetary > 0) %>%
    mutate(
      buyer = if_else(is_repeat_buyer == 1, "Repeat buyers", "One-time buyers"),
      buyer = factor(buyer, levels = c("One-time buyers", "Repeat buyers"))
    ) %>%
    ggplot(aes(x = buyer, y = monetary, fill = buyer)) +
    geom_boxplot(outlier.alpha = 0.12, width = 0.55) +
    scale_y_log10(labels = scales::comma) +
    scale_fill_manual(values = c("One-time buyers" = "#D85A30", "Repeat buyers" = "#1D9E75")) +
    labs(
      title    = "Repeat buyers tend to have higher total spend",
      subtitle = "Total spend per customer (BRL, log scale) — monetary = price only",
      x = NULL, y = "Total spend (BRL, log scale)",
      caption = "Source: rfm_table — compare distributions for CLV / targeting story"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      legend.position = "none",
      plot.title      = element_text(face = "bold", size = 14),
      plot.subtitle   = element_text(color = "gray50", size = 11)
    )
  ggsave(file.path(plot_dir, "viz6_monetary_repeat_vs_onetime.png"), p_eda6, width = 6, height = 5, dpi = 150)

  message("=== Section 1B: EDA plots saved to ", plot_dir, " ===")
}

# ==============================================================================
# SECTION 2 — Baseline CLV + revenue scenarios (original: 2. CLV/milestone2_selina_CLV.R)
# ==============================================================================
# Note: one-time buyers use flat P(repeat) = global repeat rate (~3%).
# Section 4 replaces this with model-based P(repeat) per professor feedback.
# ==============================================================================

repeat_rate <- mean(rfm_table$is_repeat_buyer)

clv_table <- rfm_table %>%
  mutate(
    p_repeat = if_else(is_repeat_buyer == 1, 1, repeat_rate),
    expected_frequency = if_else(is_repeat_buyer == 1, as.numeric(frequency), 1),
    clv_score = p_repeat * avg_order_value * expected_frequency,
    clv_tier = case_when(
      clv_score >= quantile(clv_score, 0.75, na.rm = TRUE) ~ "High",
      clv_score >= quantile(clv_score, 0.25, na.rm = TRUE) ~ "Medium",
      TRUE                                                  ~ "Low"
    )
  ) %>%
  select(
    customer_unique_id, is_repeat_buyer, frequency,
    monetary, avg_order_value,
    p_repeat, expected_frequency, clv_score, clv_tier,
    recency_days, customer_state, customer_city
  )

write_csv(clv_table, tables_path("clv_table.csv"))
saveRDS(clv_table,   tables_path("clv_table.rds"))
# Platform-wide revenue scenarios (incremental buyers × AOV × repeat frequency) are in Section 4 only
# (removed duplicate calc_impact here). Per-customer model P(repeat) enters CLV in clv_table_v2, not those scenarios.

# ==============================================================================
# SECTION 3 — Delay, experience, classifier (original: Binary Classification_Full.R)
# ==============================================================================
# Uses `rfm_table`, `orders_full`, and `clv_table` already in memory from Sections 1–2.
# (Avoids requiring `rfm_table.rds` / `orders_full.rds` in OUTPUT_DIR when only CSV
#  exists under `Clean Dataset csv/`.)

customer_base <- rfm_table %>%
  mutate(
    is_repeat_buyer = if_else(frequency >= 2, 1L, 0L),
    buyer_type = if_else(is_repeat_buyer == 1, "Repeat buyer", "One-time buyer"),
    buyer_type = factor(buyer_type, levels = c("One-time buyer", "Repeat buyer"))
  ) %>%
  select(customer_unique_id, is_repeat_buyer, buyer_type, frequency)

orders_delay <- orders_full %>%
  mutate(
    order_purchase_timestamp = ymd_hms(order_purchase_timestamp),
    order_delivered_customer_date = ymd_hms(order_delivered_customer_date),
    order_estimated_delivery_date = ymd(order_estimated_delivery_date),
    delivered_date = as.Date(order_delivered_customer_date),
    estimated_date = as.Date(order_estimated_delivery_date),
    delivery_delay_days = as.numeric(delivered_date - estimated_date)
  )

first_order_delay <- orders_delay %>%
  arrange(customer_unique_id, order_purchase_timestamp) %>%
  group_by(customer_unique_id) %>%
  slice(1) %>%
  ungroup() %>%
  select(
    customer_unique_id,
    first_order_id = order_id,
    first_purchase_time = order_purchase_timestamp,
    first_delivery_delay_days = delivery_delay_days
  )

delay_analysis <- first_order_delay %>%
  left_join(customer_base, by = "customer_unique_id") %>%
  mutate(late_flag = if_else(first_delivery_delay_days > 0, "Late", "Not late"))

customer_review <- rfm_table %>%
  mutate(is_repeat_buyer = if_else(frequency >= 2, 1L, 0L)) %>%
  select(customer_unique_id, avg_review_score, is_repeat_buyer)

delay_threshold_base <- delay_analysis %>%
  left_join(customer_review %>% select(customer_unique_id, avg_review_score), by = "customer_unique_id")

delay_bands <- delay_threshold_base %>%
  mutate(
    delay_band = case_when(
      is.na(first_delivery_delay_days) ~ "Missing",
      first_delivery_delay_days <= -14 ~ "Early by >14 days",
      first_delivery_delay_days <= -7  ~ "Early by 7 to 14 days",
      first_delivery_delay_days <= -3  ~ "Early by 3 to 7 days",
      first_delivery_delay_days <= 0   ~ "Early/on time by 0 to 3 days",
      first_delivery_delay_days <= 3   ~ "Late by 0 to 3 days",
      first_delivery_delay_days <= 7   ~ "Late by 3 to 7 days",
      first_delivery_delay_days <= 14  ~ "Late by 7 to 14 days",
      TRUE ~ "Late by >14 days"
    ),
    delay_band = factor(
      delay_band,
      levels = c(
        "Early by >14 days", "Early by 7 to 14 days", "Early by 3 to 7 days",
        "Early/on time by 0 to 3 days", "Late by 0 to 3 days", "Late by 3 to 7 days",
        "Late by 7 to 14 days", "Late by >14 days", "Missing"
      )
    )
  )

delay_threshold_table <- delay_bands %>%
  group_by(delay_band) %>%
  summarise(
    `Customers (count)` = n(),
    `Repeat rate (%)` = mean(is_repeat_buyer, na.rm = TRUE) * 100,
    `Average first-order delay (days)` = mean(first_delivery_delay_days, na.rm = TRUE),
    `Average review score (1 to 5)` = mean(avg_review_score, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ round(.x, 2)))

write_csv(delay_threshold_table, tables_path("delay_threshold_table.csv"))

experience_base <- rfm_table %>%
  mutate(
    is_repeat_buyer = if_else(frequency >= 2, 1L, 0L),
    buyer_type = if_else(is_repeat_buyer == 1, "Repeat buyer", "One-time buyer"),
    buyer_type = factor(buyer_type, levels = c("One-time buyer", "Repeat buyer"))
  ) %>%
  select(
    customer_unique_id, is_repeat_buyer, buyer_type,
    avg_review_score, avg_installments, avg_freight,
    used_credit_card, used_boleto, used_voucher
  )

experience_summary <- experience_base %>%
  group_by(buyer_type) %>%
  summarise(
    `Customers (count)` = n(),
    `Average review score (1 to 5)` = mean(avg_review_score, na.rm = TRUE),
    `Median review score (1 to 5)` = median(avg_review_score, na.rm = TRUE),
    `Average installments (count)` = mean(avg_installments, na.rm = TRUE),
    `Average freight (BRL)` = mean(avg_freight, na.rm = TRUE),
    `Used credit card (%)` = mean(used_credit_card, na.rm = TRUE) * 100,
    `Used boleto (%)` = mean(used_boleto, na.rm = TRUE) * 100,
    `Used voucher (%)` = mean(used_voucher, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ round(.x, 2)))

write_csv(experience_summary, tables_path("experience_summary.csv"))

combined <- rfm_table %>%
  mutate(
    is_repeat_buyer = if_else(frequency >= 2, 1L, 0L),
    buyer_type = if_else(is_repeat_buyer == 1, "Repeat buyer", "One-time buyer"),
    buyer_type = factor(buyer_type, levels = c("One-time buyer", "Repeat buyer"))
  ) %>%
  left_join(
    clv_table %>% select(customer_unique_id, clv_score, clv_tier),
    by = "customer_unique_id"
  )

model_data <- combined %>%
  left_join(first_order_delay, by = "customer_unique_id") %>%
  select(
    customer_unique_id,
    is_repeat_buyer,
    clv_score,
    clv_tier,
    monetary,
    avg_review_score,
    avg_installments,
    avg_freight,
    used_credit_card,
    used_boleto,
    used_voucher,
    first_delivery_delay_days
  )

model_data_clean <- model_data %>% drop_na()

train_index <- sample(seq_len(nrow(model_data_clean)), size = 0.7 * nrow(model_data_clean))
train_data <- model_data_clean[train_index, ]
test_data  <- model_data_clean[-train_index, ]

repeat_model <- glm(
  is_repeat_buyer ~ monetary + avg_review_score +
    avg_installments + avg_freight +
    used_credit_card + used_boleto +
    used_voucher + first_delivery_delay_days,
  data = train_data,
  family = binomial()
)

test_pred <- test_data %>%
  mutate(
    p_repeat = predict(repeat_model, newdata = test_data, type = "response"),
    pred_class_050 = if_else(p_repeat >= 0.50, 1L, 0L),
    pred_class_010 = if_else(p_repeat >= 0.10, 1L, 0L),
    pred_class_005 = if_else(p_repeat >= 0.05, 1L, 0L)
  )

roc_obj <- roc(test_pred$is_repeat_buyer, test_pred$p_repeat, quiet = TRUE)
auc_value <- round(as.numeric(auc(roc_obj)), 3)

feature_importance <- tidy(repeat_model) %>%
  filter(term != "(Intercept)") %>%
  mutate(
    odds_ratio = exp(estimate),
    abs_estimate = abs(estimate),
    direction = if_else(estimate > 0, "Increases P(repeat)", "Decreases P(repeat)"),
    significance = case_when(
      p.value < 0.001 ~ "***",
      p.value < 0.01  ~ "**",
      p.value < 0.05  ~ "*",
      TRUE            ~ ""
    )
  ) %>%
  arrange(desc(abs_estimate)) %>%
  mutate(
    rank = row_number(),
    estimate = round(estimate, 4),
    odds_ratio = round(odds_ratio, 4),
    p.value = round(p.value, 4)
  ) %>%
  select(rank, term, estimate, odds_ratio, direction, p.value, significance)

write_csv(feature_importance, tables_path("feature_importance_ranking.csv"))

# --- ROC Curve Plot (ggplot2 version) ---
roc_data <- data.frame(
  specificity = roc_obj$specificities,
  sensitivity = roc_obj$sensitivities
)

roc_plot <- ggplot(roc_data, aes(x = 1 - specificity, y = sensitivity)) +
  geom_line(color = "#002060", linewidth = 1.2) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#E47867", linewidth = 0.8) +
  geom_ribbon(aes(ymin = 0, ymax = sensitivity), fill = "#002060", alpha = 0.1) +
  annotate("text", x = 0.55, y = 0.35, label = paste0("AUC = ", auc_value),
           size = 6, fontface = "bold", color = "#002060") +
  labs(
    title = "ROC Curve — Repeat Buyer Classifier",
    x = "False Positive Rate (1 - Specificity)",
    y = "True Positive Rate (Sensitivity)"
  ) +
  coord_equal() +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14, color = "#002060"),
    panel.grid.minor = element_blank()
  )
print(roc_plot)
ggsave(plots_path("plot_roc_curve.png"), roc_plot, width = 6, height = 5.5, dpi = 150)

# --- Feature Importance Plot ---
feature_importance_plot <- ggplot(feature_importance,
                                  aes(x = reorder(term, abs(estimate)), y = estimate, fill = direction)) +
  geom_col(width = 0.7) +
  coord_flip() +
  scale_fill_manual(values = c(
    "Increases P(repeat)" = "#1D9E75",
    "Decreases P(repeat)" = "#D85A30"
  )) +
  labs(
    title    = "Feature Importance: Repeat Buyer Classifier",
    subtitle = "Logistic regression coefficients (larger magnitude = stronger effect)",
    x = NULL, y = "Coefficient (log-odds)", fill = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position    = "bottom",
    plot.title         = element_text(face = "bold", size = 14),
    plot.subtitle      = element_text(color = "gray50", size = 11),
    panel.grid.major.y = element_blank()
  )
print(feature_importance_plot)
ggsave(plots_path("plot_feature_importance.png"), feature_importance_plot, width = 8, height = 5, dpi = 150)

customer_p_repeat <- model_data_clean %>%
  mutate(p_repeat = predict(repeat_model, newdata = model_data_clean, type = "response")) %>%
  arrange(desc(p_repeat)) %>%
  mutate(
    p_repeat_band = case_when(
      p_repeat >= 0.20 ~ "Very high",
      p_repeat >= 0.10 ~ "High",
      p_repeat >= 0.05 ~ "Medium",
      p_repeat >= 0.02 ~ "Low",
      TRUE ~ "Very low"
    ),
    p_repeat_band = factor(
      p_repeat_band,
      levels = c("Very high", "High", "Medium", "Low", "Very low")
    )
  )

write_csv(
  customer_p_repeat %>%
    select(customer_unique_id, clv_tier, clv_score, p_repeat, p_repeat_band, is_repeat_buyer),
  tables_path("customer_p_repeat_scores.csv")
)

# ==============================================================================
# SECTION 4 — CLV v2 + targeting P&L (original: 5. .../milestone2_selina_CLV_v3.R)
# ==============================================================================
# Uses model P(repeat) for one-time buyers; repeat buyers stay at P(repeat)=1.
# Targeting: “High-Potential Dormant Buyers” — one-time, P(repeat) ≥ 10%.
# ==============================================================================

p_repeat_scores <- customer_p_repeat %>% select(customer_unique_id, p_repeat)

avg_order_val_all <- mean(rfm_table$avg_order_value, na.rm = TRUE)
avg_repeat_freq   <- mean(rfm_table$frequency[rfm_table$is_repeat_buyer == 1], na.rm = TRUE)
current_rate      <- mean(rfm_table$is_repeat_buyer)
cost_per_customer <- 15.00  # BRL 10 voucher + BRL 5 delivery (Milestone 3 plan)

clv_table_v2 <- rfm_table %>%
  left_join(
    p_repeat_scores %>% rename(p_repeat_model = p_repeat),
    by = "customer_unique_id"
  ) %>%
  mutate(
    p_repeat           = if_else(is_repeat_buyer == 1, 1, p_repeat_model),
    expected_frequency = if_else(is_repeat_buyer == 1, as.numeric(frequency), 1),
    clv_score          = p_repeat * avg_order_value * expected_frequency,
    clv_tier           = case_when(
      clv_score >= quantile(clv_score, 0.75, na.rm = TRUE) ~ "High",
      clv_score >= quantile(clv_score, 0.25, na.rm = TRUE) ~ "Medium",
      TRUE                                                  ~ "Low"
    )
  ) %>%
  select(
    customer_unique_id, is_repeat_buyer, frequency,
    monetary, avg_order_value, p_repeat, expected_frequency,
    clv_score, clv_tier, recency_days, customer_state, customer_city
  )

saveRDS(clv_table_v2, tables_path("clv_table_v2.rds"))
write_csv(clv_table_v2, tables_path("clv_table_v2.csv"))

revenue_impact_table <- bind_rows(
  tibble(
    scenario             = "3% → 5% repeat rate",
    current_rate_pct     = round(current_rate * 100, 1),
    new_rate_pct         = 5,
    incremental_buyers   = round(nrow(clv_table_v2) * (0.05 - current_rate)),
    avg_order_value_brl  = round(avg_order_val_all, 2),
    avg_repeat_frequency = round(avg_repeat_freq, 2),
    incremental_rev_brl  = round(nrow(clv_table_v2) * (0.05 - current_rate) * avg_order_val_all * avg_repeat_freq)
  ),
  tibble(
    scenario             = "3% → 6% repeat rate",
    current_rate_pct     = round(current_rate * 100, 1),
    new_rate_pct         = 6,
    incremental_buyers   = round(nrow(clv_table_v2) * (0.06 - current_rate)),
    avg_order_value_brl  = round(avg_order_val_all, 2),
    avg_repeat_frequency = round(avg_repeat_freq, 2),
    incremental_rev_brl  = round(nrow(clv_table_v2) * (0.06 - current_rate) * avg_order_val_all * avg_repeat_freq)
  )
)

write_csv(revenue_impact_table, tables_path("revenue_impact_table.csv"))

targeting_table <- clv_table_v2 %>%
  filter(is_repeat_buyer == 0, p_repeat >= 0.10) %>%
  mutate(
    expected_revenue = p_repeat * avg_order_val_all,
    expected_net_profit = expected_revenue - cost_per_customer
  )

targeting_pl_table <- tibble(
  metric = c(
    "Customers targeted (P >= 10%)",
    "Total intervention cost (BRL)",
    "Expected conversions",
    "Expected revenue (BRL)",
    "Net profit (BRL)"
  ),
  value = c(
    nrow(targeting_table),
    round(nrow(targeting_table) * cost_per_customer),
    round(sum(targeting_table$p_repeat)),
    round(sum(targeting_table$expected_revenue)),
    round(sum(targeting_table$expected_revenue) - nrow(targeting_table) * cost_per_customer)
  )
)

write_csv(targeting_pl_table, tables_path("targeting_pl_table.csv"))

if (SAVE_PLOT_FILES) {
  p1 <- clv_table_v2 %>%
    mutate(buyer_type = if_else(is_repeat_buyer == 1, "Repeat buyer", "One-time buyer")) %>%
    filter(clv_score <= quantile(clv_score, 0.99, na.rm = TRUE)) %>%
    ggplot(aes(x = clv_score, fill = buyer_type)) +
    geom_histogram(bins = 50, alpha = 0.7, position = "identity") +
    scale_fill_manual(values = c("One-time buyer" = "#a8c5da", "Repeat buyer" = "#2c6e9b")) +
    labs(title = "CLV Score Distribution by Buyer Type", x = "CLV Score (BRL)", y = "Count", fill = NULL) +
    theme_minimal()
  ggsave(plots_path("plot_clv_distribution.png"), p1, width = 8, height = 5, dpi = 150)

  p2 <- clv_table_v2 %>%
    filter(is_repeat_buyer == 0, !is.na(p_repeat)) %>%
    ggplot(aes(x = p_repeat)) +
    geom_histogram(bins = 40, fill = "#2c6e9b", alpha = 0.8) +
    geom_vline(xintercept = 0.10, linetype = "dashed", color = "red") +
    labs(title = "Predicted Repeat Probability — One-Time Buyers", x = "P(repeat)", y = "Count") +
    theme_minimal()
  ggsave(plots_path("plot_p_repeat_one_time.png"), p2, width = 8, height = 5, dpi = 150)
}

# ==============================================================================
# SECTION 5 — Randomized experiment + scale-up economics
# (original tail: 6. Randomized Experiment Design/Randomized Experiment Design.R)
# ==============================================================================

baseline_repeat_rate <- current_rate  # alias used in power.prop.test below

target_segment <- customer_p_repeat %>%
  filter(is_repeat_buyer == 0, p_repeat >= 0.10, !is.na(p_repeat))

n_target <- nrow(target_segment)

target_segment <- target_segment %>%
  mutate(
    expected_revenue = p_repeat * avg_order_val_all,
    expected_net_profit = expected_revenue - cost_per_customer
  )

scale_cost <- n_target * cost_per_customer
scale_expected_conversions <- sum(target_segment$p_repeat)
scale_expected_revenue <- sum(target_segment$expected_revenue)
scale_net_profit <- scale_expected_revenue - scale_cost

assumed_lift <- 0.02
power_calc <- power.prop.test(
  p1 = baseline_repeat_rate,
  p2 = baseline_repeat_rate + assumed_lift,
  power = 0.80,
  sig.level = 0.05,
  alternative = "two.sided"
)

sample_per_group <- ceiling(power_calc$n)
total_sample <- sample_per_group * 2

experiment_cost <- sample_per_group * cost_per_customer
expected_control_conversions <- sample_per_group * baseline_repeat_rate
expected_treatment_conversions <- sample_per_group * (baseline_repeat_rate + assumed_lift)
incremental_conversions_exp <- expected_treatment_conversions - expected_control_conversions
incremental_revenue_exp <- incremental_conversions_exp * avg_order_val_all
net_profit_experiment <- incremental_revenue_exp - experiment_cost

experiment_summary <- tibble(
  Phase = c("Experiment", "Experiment", "Experiment", "Scale-up", "Scale-up", "Scale-up", "Scale-up"),
  Metric = c(
    "Sample size (total)",
    "Cost (BRL 15/customer)",
    "Expected net profit",
    "Target segment",
    "Cost (BRL 15/customer)",
    "Expected conversions",
    "Net profit (per cycle)"
  ),
  Value = c(
    paste0(format(total_sample, big.mark = ","), " customers"),
    paste0("BRL ", format(round(experiment_cost), big.mark = ",")),
    paste0("BRL ", format(round(net_profit_experiment), big.mark = ",")),
    paste0(format(n_target, big.mark = ","), " customers"),
    paste0("BRL ", format(round(scale_cost), big.mark = ",")),
    round(scale_expected_conversions),
    paste0("BRL ", format(round(scale_net_profit), big.mark = ","))
  )
)

write_csv(experiment_summary, tables_path("experiment_summary.csv"))

# ==============================================================================
# SECTION 6 — Segmentation matrix (original: 7. Segmentation Matrix/segmentation matrix code.r)
# ==============================================================================
# Uses clv_table_v2 in memory; maps to segment names + interventions.
# ==============================================================================

name_champions <- "Loyalty Champions"
name_high_pot  <- "High-Potential Dormant Buyers"
name_med_pot   <- "Medium-Potential"
name_low_pot   <- "Low-Potential"
name_passives  <- "Low-Value Passives"

customer_base_seg <- clv_table_v2 %>%
  mutate(
    segment_name = case_when(
      is_repeat_buyer == 1 ~ name_champions,
      is_repeat_buyer == 0 & p_repeat >= 0.10 ~ name_high_pot,
      is_repeat_buyer == 0 & p_repeat >= 0.05 ~ name_med_pot,
      is_repeat_buyer == 0 & p_repeat >= 0.02 ~ name_low_pot,
      TRUE ~ name_passives
    )
  )

segmentation_matrix <- customer_base_seg %>%
  group_by(segment_name) %>%
  summarise(
    `Size (N)` = n(),
    `Avg. Granular CLV (BRL)` = round(mean(clv_score, na.rm = TRUE), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(`Avg. Granular CLV (BRL)`)) %>%
  mutate(
    `Recommended Intervention` = case_when(
      segment_name == name_champions ~ "VIP retention: early access to new categories.",
      segment_name == name_high_pot  ~ "Direct re-engagement: BRL 10 targeted voucher (+ delivery subsidy as costed in P&L).",
      segment_name == name_med_pot   ~ "Soft nurture: highlight installment options at checkout.",
      segment_name == name_low_pot   ~ "Passive reach: standard lifecycle email.",
      segment_name == name_passives  ~ "Do not target: no incremental retention spend."
    )
  )

write_csv(segmentation_matrix, tables_path("segmentation_matrix_final.csv"))

# ==============================================================================
# Run complete
# ==============================================================================

message("\n=== Group 3 master script finished. Key outputs in output/ ===")
message("AUC (holdout): ", auc_value)
message("Targeting P&L saved: ", tables_path("targeting_pl_table.csv"))
message("Experiment summary: ", tables_path("experiment_summary.csv"))
message("Segmentation matrix: ", tables_path("segmentation_matrix_final.csv"))
if (RUN_MILESTONE2_EDA) {
  message("Milestone 2 EDA plots: ", OUTPUT_PLOTS_DIR, " (viz1_repeat_vs_onetime.png … viz6_monetary_repeat_vs_onetime.png)")
}
