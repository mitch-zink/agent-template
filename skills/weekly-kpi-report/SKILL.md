---
name: weekly-kpi-report
description: >-
  Produce a recurring KPI digest for a team (usually run by a weekday-morning
  routine); also when someone asks "how did we do this week?"
---
# Weekly KPI report

1. **Read the team's KPI list** from its playbook: the 4-8 metrics it actually manages to, with targets if they exist. Don't invent extra ones.
2. **Pull each KPI** for the completed week (never the partial current one) with the prior week and the same week last year, using `answer-metric-question` rules.
3. **Rank by what needs attention:** off target, biggest moves, broken trends. Healthy, steady metrics get one line total.
4. **Explain the top one or two movers** with a quick decomposition (`investigate-metric-change`, steps 2-4, kept short).
5. **Write it to be skimmed:**
   - one-sentence headline ("Revenue up 6% on DTC strength; CAC worsening for the third week")
   - each KPI: value, change, status (on track / watch / off track)
   - up to three things worth a human's attention, each with an owner if known
   - links to the dashboards behind each number
6. **Deliver to the team's channel.** Posting outside the team, or anywhere external, needs approval.

If nothing changed meaningfully, say so in one line. A quiet week is a finding.
