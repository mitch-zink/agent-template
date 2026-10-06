# cron.d

One routine per file. Folder = rough cadence (for humans; the schedule in frontmatter is authoritative). Filename = `<id>__<schedule>.md`.

```markdown
---
id: kpi-report
enabled: true
mode: task            # task | heartbeat
schedule:
  kind: cron          # cron | interval | daily | runonce
  cron: "47 7 * * 1-5"
  timezone: America/New_York
# or, instead of schedule:
# trigger: { type: github, repo: owner/name, pr: 123, events: [ci-failed, pr-merged] }
delivery: []          # channels to post to; empty = runtime default
expires: null         # ISO date for finite watches
---
Prompt: what to do, written as intent. See skills/routines.
```

- `_archive/`: retired routines, kept for reference.
- `runonce/`: one-shot reminders; delete after firing.
- Pause with `enabled: false`, don't delete, when an auth failure recurs.
