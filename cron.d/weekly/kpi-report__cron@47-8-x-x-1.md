---
id: kpi-report
enabled: false
mode: task
schedule:
  kind: cron
  cron: "47 8 * * 1"
  timezone: America/New_York
delivery: []
---
Run the `data-quality-check` skill on the tables behind the team's metrics in USER.md. If any check fails, post that instead and hold the report.

Otherwise run the `weekly-kpi-report` skill for last completed week and post it to the team channel. Follow PROACTIVE_PREFERENCES.md for what to include and how it should read.
