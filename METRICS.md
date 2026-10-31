# Metric definitions

These definitions are the single source of truth for every number on the dashboard. Each metric is calculated once, in dbt (`fct_cases` and `mart_kpi_daily`), and Looker Studio only aggregates the stored numerators and denominators. That way every page and every filter returns the same answer.

| Metric | Definition | Grain / notes |
|---|---|---|
| **Cases created** | Count of distinct cases by `created_at` date | Duplicates are removed in staging |
| **Cases resolved** | Count of cases by `resolved_at` date | Excludes cases with an invalid `resolved_at` |
| **Open backlog (end of day)** | Cumulative cases created − cumulative cases resolved, as of the end of the day | Excludes cases with an invalid `resolved_at` |
| **First-response SLA rate** | Cases answered within their target ÷ cases with a first response | Target depends on support tier × priority (`sla_targets`). Cases with no response yet are excluded |
| **Median / P90 time to first response** | 50th / 90th percentile of minutes from creation to first agent response | Medians are not re-aggregated across days; use `fct_cases` for period medians |
| **Median resolution time** | 50th percentile of hours from creation to resolution | Closed cases with a valid `resolved_at` only |
| **Escalation rate** | Escalated cases ÷ cases created | |
| **Reopen count** | Resolved cases later reopened, by resolved date | |
| **CSAT satisfaction rate** | Surveys scoring 4 or 5 ÷ valid surveys | Latest valid survey per case; scores outside 1–5 and orphan surveys excluded |
| **Average CSAT** | Sum of valid scores ÷ valid surveys | |

## How to re-aggregate in Looker Studio

Rates must be recalculated from their parts, not averaged. For example, the monthly SLA rate is:

```
SUM(first_responses_within_sla) / SUM(first_responses_measured)
```

Averaging the daily `first_response_sla_rate` would give a low-volume Sunday the same weight as a busy Monday.
