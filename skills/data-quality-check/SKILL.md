---
name: data-quality-check
description: >-
  When numbers look wrong, a dashboard seems stale, or a routine should verify
  data before a report goes out.
---
# Data quality check

Run these against the tables behind the metric in question, cheapest first:

1. **Freshness:** latest timestamp vs expected cadence. A daily table more than a day behind is stale.
2. **Volume:** today's (or the latest load's) row count vs the trailing 7-day range. Report a near-zero or doubled load immediately.
3. **Completeness:** null rate on key columns (ids, dates, amounts) vs normal.
4. **Uniqueness:** duplicate primary keys or duplicate business keys (the same order twice).
5. **Validity:** values out of range (negative quantities, future dates, unknown categories).
6. **Consistency:** the same total from two sources that should agree (source system vs warehouse, mart vs dashboard).

Report each check as pass / warn / fail with the observed number and the expected range. On a fail:
- say what it affects (which dashboards and reports)
- hold any report that depends on it, and say why
- propose a ticket with the evidence; filing it is a write and waits for approval
