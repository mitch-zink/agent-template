---
name: answer-metric-question
description: >-
  When someone asks for a number: revenue, orders, conversion, spend, any KPI,
  for a period, segment or channel.
---
# Answer a metric question

1. **Pin the definition.** Use the team's canonical definition (team playbook or data dictionary). If two definitions are plausible and the answer changes, ask one short question; otherwise pick the canonical one and say which.
2. **Pin the window.** Resolve "last week", "this quarter", "MTD" to exact dates in the business's timezone. State them.
3. **Use the governed source.** Prefer the same table or tool the dashboard uses, so chat and dashboard agree. Never hand-write a query against raw tables when a curated one exists.
4. **Sanity check before answering.** Is the latest day complete? Does the total roughly match the dashboard? Is anything an order of magnitude off from the prior period? If something looks wrong, say so instead of reporting it.
5. **Answer first, then context.** Lead with the number and the comparison that matters (vs prior period, vs target). Then one line on the biggest driver if it's obvious.
6. **Show your work** for technical users: the source and the query. For everyone else, name the source in one line.
7. **Flag limits:** data freshness, partial periods, known gaps.

Don't recite a table the chart already shows. Narrate what matters.
