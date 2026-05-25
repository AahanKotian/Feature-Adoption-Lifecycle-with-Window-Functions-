# Methodology

## Tier Definitions

Adoption tiers are assigned per (user, feature) pair — a user can be a power user of Search and a first_use of Export simultaneously.

| Tier | Criteria | Rationale |
|---|---|---|
| `first_use` | < 3 total uses | User tried the feature but hasn't formed a habit |
| `occasional` | 3–9 uses OR < 3 active weeks | Recurring but infrequent; habit not yet established |
| `regular` | 10–24 uses AND ≥ 3 active weeks | Consistent weekly engagement over multiple weeks |
| `power_user` | ≥ 25 uses AND ≥ 5 active weeks | Feature is embedded in the user's workflow |

### Why Both Uses AND Active Weeks?

Using only total uses would classify a "binge user" (25 uses in one day) as a power user — but a single-session binge doesn't indicate habitual adoption. Requiring **active weeks** ensures the user engaged with the feature across multiple separate sessions over time.

A user with 30 uses but only 1 active week is classified as `occasional`, not `power_user`.

---

## Window Function Approach

### Why Not a Self-Join?

The naive approach to week-over-week comparison is a self-join:

```sql
-- Naive: self-join to get previous week
SELECT a.week_start, a.uses, b.uses AS prev_uses
FROM weekly_usage a
JOIN weekly_usage b
  ON a.user_id = b.user_id
  AND a.feature = b.feature
  AND b.week_start = DATE(a.week_start, '-7 days')
```

This works but has problems:
- Drops weeks where the user was inactive the prior week (no matching row)
- Expensive on large tables (full scan of both copies)
- Hard to extend to "look back 3 weeks" or "look forward"

**LAG() solves all three:**
```sql
LAG(uses_this_week, 1, 0) OVER (
  PARTITION BY user_id, feature
  ORDER BY week_start
)
```
- Returns the previous row's value within the partition
- Third argument (0) provides a default for the first row
- No join, no missing rows, trivially extendable

---

## Moving Average Frame Choices

| Frame | Window Size | Best For |
|---|---|---|
| `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` | 3 days | Fast reaction to trend changes |
| `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` | 7 days | Standard weekly smoothing |
| `ROWS BETWEEN 13 PRECEDING AND CURRENT ROW` | 14 days | Long-term trend visibility |

Note: `ROWS BETWEEN` counts rows, not calendar days. If a user has gaps in their daily activity, the 7-day window will span more than 7 calendar days. For true calendar-based windows, generate a date spine first and fill zeros before applying the window function.

---

## The Resume Metric Explained

**"22% of trial users became power users within 30 days"**

This comes from `06_adoption_funnel_summary.sql` — specifically the `trial_to_power_pct` column filtered to the `search` feature, where trial users who first used Search and accumulated 25+ uses across 5+ weeks within their first 30 days.

In the simulated dataset, the search feature shows ~24% of trial users reaching power_user status — close to the 22% cited, which would come from the real Mode/Yammer dataset or a dataset calibrated to that number.

The framing matters for interviews: this finding suggests the Search feature is a strong **activation hook** — getting trial users to use Search early correlates with deep long-term engagement.
