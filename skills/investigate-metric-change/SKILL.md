---
name: investigate-metric-change
description: >-
  When a metric moved unexpectedly ("why did conversion drop?", "sales spiked
  Tuesday") or an alert fired and someone needs the cause.
---
# Investigate a metric change

1. **Confirm it's real.** Check freshness, partial days, late-arriving data, duplicates, and recent pipeline or definition changes. A large share of "drops" are data problems; rule that out first and say how.
2. **Size it.** Absolute and relative change vs the right baseline: same weekday last week, same period last year, trailing average. One baseline is not enough for a seasonal business.
3. **Decompose.** Break the change down by the dimensions that usually explain it (channel, region, product, customer type, platform). Find where most of the delta lives. Rate vs volume: did fewer people arrive, or did fewer convert?
4. **Look for a cause in time.** Releases, campaigns starting or stopping, price changes, stockouts, outages, holidays, competitor events. Line the change up against them.
5. **State a conclusion with a confidence level.** "Most of the drop (about 70%) is paid social traffic, which fell after the campaign ended on the 12th. Conversion held steady." If you can't find a cause, say what you ruled out.
6. **Recommend one next step:** who should look, what to watch, whether to open a ticket. Filing the ticket is a write, so it waits for approval.
