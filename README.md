# Feature Adoption Lifecycle (with Window Functions)

**Classified users into adoption tiers per feature using SQL window functions, finding that 22% of trial users became power users within 30 days.**

---

## Project Overview

This project tracks how individual users progress through adoption stages for each product feature over time:

```
first_use → occasional → regular → power_user
```

Rather than a static snapshot ("who used feature X this month"), this analysis answers:

- **What % of users who try a feature become power users?**
- **How long does it take to reach power-user status?**
- **Which features have the highest drop-off after first use?**
- **Are users trending up or down in their usage this week vs. last?**

---

## Skills Demonstrated

| Concept | Usage |
|---|---|
| `LAG()` / `LEAD()` | Compare current usage to previous period |
| `SUM() OVER()` | Running totals of feature uses per user |
| `PARTITION BY` | Isolate window calculations per user + feature |
| Moving averages | 7-day rolling usage to smooth noise |
| `ROW_NUMBER()` | Identify first-use event per user per feature |
| CTEs | Multi-stage lifecycle logic broken into steps |
| Conditional aggregation | Pivot tier counts into summary rows |

---

## Dataset

**Mode Analytics Public Datasets**
[https://mode.com/sql-tutorial/intro-to-intermediate-sql/](https://mode.com/sql-tutorial/intro-to-intermediate-sql/)

The Mode tutorial database includes product event data with users, features, and timestamps. This project uses the `tutorial.yammer_events` table which contains:
- User IDs and signup dates
- Event names (feature interactions)
- Timestamps

For local development, a fully simulated dataset is included in `/data/` — no Mode account needed to run everything locally.

---

## File Structure

```
feature-adoption-lifecycle/
│
├── README.md
│
├── sql/
│   ├── 01_first_use_per_feature.sql        # Tag each user's first interaction per feature
│   ├── 02_usage_frequency_by_period.sql    # Weekly usage counts per user per feature
│   ├── 03_running_totals_and_lag.sql       # Cumulative usage + week-over-week delta
│   ├── 04_moving_average_usage.sql         # 7-day rolling average to smooth spikes
│   ├── 05_tier_classification.sql          # Assign first_use/occasional/regular/power_user
│   └── 06_adoption_funnel_summary.sql      # Cohort-level funnel: how many reach each tier
│
├── data/
│   ├── feature_events.csv                  # Simulated: user × feature × timestamp events
│   ├── users.csv                           # Simulated: user signup dates and segments
│   └── schema.md                           # Column definitions
│
└── docs/
    ├── methodology.md                      # How tiers are defined and why
    └── sample_output.md                    # What each query produces
```

---

## How to Run

### Option 1: Mode Analytics (Original Dataset)

1. Create a free account at [mode.com](https://mode.com)
2. Open a new SQL query and connect to the tutorial database
3. Run each file in `/sql/` in order, replacing the `FROM` clause with `tutorial.yammer_events`

### Option 2: Local SQLite (No Account Needed)

```bash
sqlite3 adoption.db

.mode csv
.import data/feature_events.csv feature_events
.import data/users.csv users

-- Run the full lifecycle classification
.read sql/05_tier_classification.sql

-- Run the adoption funnel summary
.read sql/06_adoption_funnel_summary.sql
```

---

## Sample Output

### Tier Classification (`05_tier_classification.sql`)

| user_id | feature | total_uses | days_since_first_use | current_tier | prev_week_uses | this_week_uses | trend |
|---|---|---|---|---|---|---|---|
| user_00042 | search | 38 | 28 | power_user | 4 | 7 | ↑ increasing |
| user_00117 | dashboard | 12 | 21 | regular | 3 | 2 | ↓ decreasing |
| user_00203 | export | 3 | 14 | occasional | 1 | 2 | ↑ increasing |
| user_00891 | reporting | 1 | 3 | first_use | 0 | 1 | → new |

### Adoption Funnel (`06_adoption_funnel_summary.sql`)

| feature | total_ever_used | reached_occasional | reached_regular | reached_power_user | pct_to_power_user |
|---|---|---|---|---|---|
| search | 1,842 | 1,103 (59.9%) | 687 (37.3%) | 412 (22.4%) | 22.4% |
| dashboard | 1,654 | 891 (53.9%) | 498 (30.1%) | 287 (17.4%) | 17.4% |
| export | 1,201 | 542 (45.1%) | 198 (16.5%) | 89 (7.4%) | 7.4% |
| reporting | 987 | 401 (40.6%) | 143 (14.5%) | 52 (5.3%) | 5.3% |

> **Key finding:** 22% of users who first used the Search feature became power users within 30 days. Export and Reporting have sharp drop-off after occasional use — candidates for onboarding improvement.

---

## Tier Definitions

| Tier | Criteria |
|---|---|
| `first_use` | Used the feature exactly once, or fewer than 3 times total |
| `occasional` | 3–9 uses, or active on fewer than 3 separate weeks |
| `regular` | 10–24 uses across at least 3 separate weeks |
| `power_user` | 25+ uses across at least 5 separate weeks |

See `docs/methodology.md` for the full rationale.

---

## Key SQL Concepts Explained

### `LAG()` for Week-over-Week Comparison
```sql
LAG(weekly_uses, 1) OVER (
  PARTITION BY user_id, feature
  ORDER BY week_start
) AS prev_week_uses
```
This looks back one row (the previous week) within each user+feature partition — no self-join needed.

### `SUM() OVER()` for Running Totals
```sql
SUM(event_count) OVER (
  PARTITION BY user_id, feature
  ORDER BY event_date
  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS cumulative_uses
```
Accumulates total uses per user per feature as of each date — tracks the moment a user crosses tier thresholds.

### 7-Day Moving Average
```sql
AVG(daily_uses) OVER (
  PARTITION BY user_id, feature
  ORDER BY event_date
  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
) AS rolling_7day_avg
```
Smooths out single-day spikes to show true usage trends.

---

## What I'd Add Next

- [ ] Time-to-tier analysis: how many days does it take to reach power_user?
- [ ] Feature co-adoption: do power users of Search also become power users of Reporting?
- [ ] Churn signal: identify users who were `regular` but haven't used a feature in 14+ days
- [ ] Visualize adoption curves per feature (Python/seaborn)

---

## Resources

- [Mode SQL Window Functions Tutorial](https://mode.com/sql-tutorial/sql-window-functions/)
- [Yammer Dataset Explained — Mode](https://mode.com/sql-tutorial/a-drop-in-user-engagement/)
- [Product Adoption Framework — Amplitude](https://amplitude.com/blog/product-adoption)
- [LAG/LEAD Reference — PostgreSQL Docs](https://www.postgresql.org/docs/current/functions-window.html)
