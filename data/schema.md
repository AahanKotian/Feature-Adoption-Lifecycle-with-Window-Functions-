# Dataset Schema

## Table 1: `feature_events` (`feature_events.csv`)

One row per user interaction with a product feature. Mirrors the structure of `tutorial.yammer_events` from Mode Analytics.

| Column | Type | Description |
|---|---|---|
| `user_id` | TEXT | Unique user identifier (e.g. `user_00042`) |
| `feature` | TEXT | Feature name (see values below) |
| `event_type` | TEXT | Always `engagement` in this dataset |
| `event_time` | TEXT | Timestamp in `YYYY-MM-DD HH:MM:SS` format |

**Feature Values:**

| Feature | Description |
|---|---|
| `search` | In-app search functionality |
| `dashboard` | Main analytics dashboard |
| `export` | Data export to CSV/PDF |
| `reporting` | Custom report builder |
| `notifications` | Notification settings and alerts |
| `bulk_edit` | Bulk editing of records |

**Volume:** ~60,000 events across 1,500 users and 6 features over 12 months.

---

## Table 2: `users` (`users.csv`)

One row per user. Contains signup date and account type.

| Column | Type | Description |
|---|---|---|
| `user_id` | TEXT | Foreign key → `feature_events.user_id` |
| `user_type` | TEXT | One of: `trial`, `paid`, `enterprise` |
| `signup_date` | TEXT | Date the user created their account (`YYYY-MM-DD`) |

**User Type Distribution:**

| Type | Share | Description |
|---|---|---|
| `trial` | ~45% | Free trial accounts (14-day window) |
| `paid` | ~40% | Paying individual/team subscribers |
| `enterprise` | ~15% | Enterprise contract accounts |

---

## How the Tables Join

```sql
FROM feature_events fe
LEFT JOIN users u ON fe.user_id = u.user_id
```

The `users` table is used in Step 6 to break down the adoption funnel by user type — specifically to find what % of **trial** users reach power_user status.

---

## Mode Analytics Equivalent

To run these queries on the real Mode dataset:

```sql
-- Replace:
FROM feature_events

-- With:
FROM tutorial.yammer_events
WHERE event_type = 'engagement'

-- Column mapping:
-- user_id     → user_id
-- feature     → event_name  (each event_name is a feature)
-- event_time  → occurred_at
```

The `users` table maps to `tutorial.yammer_users`:
```sql
-- Replace:
FROM users

-- With:
FROM tutorial.yammer_users

-- Column mapping:
-- user_id     → user_id
-- user_type   → (not directly available — use activated_at IS NULL as trial proxy)
-- signup_date → created_at
```
