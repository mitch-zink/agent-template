---
id: data-freshness
enabled: false
mode: task
schedule:
  kind: cron
  cron: "17 8 * * 1-5"
  timezone: America/New_York
delivery: []
---
Run the freshness and volume checks from the `data-quality-check` skill on the team's sources of truth. Post only if something is stale or off; a clean result is a one-line note in today's daily memory file.
