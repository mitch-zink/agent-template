---
name: routines
description: >-
  Read before creating or changing anything recurring, scheduled, or
  event-driven: a reminder, digest, monitor, "let me know when", or a change to
  an existing routine.
---
# Routines

A routine is a saved prompt plus a trigger. Each one is a markdown file in `cron.d/<cadence>/<id>__<schedule>.md` (see `cron.d/README.md` for the file format).

## Writing the prompt
- Write intent, not a frozen tool recipe. Don't bake tool names, arguments, or schemas into it; a connector can change between runs, so each run looks its tools up fresh.
- If the routine must tell someone something, say so explicitly ("message the user with...") and let the run pick the channel.
- A routine can point at a skill ("Run the `morning-digest` skill, then..."). That is a pointer, not a copy.

## Choosing a schedule
- Pick the cadence for when the result is useful, not the most frequent one possible. Morning digest, hourly check, weekday reminder. Tighten only when delay has a real cost.
- Default window is weekdays during waking hours (about 8am to 7pm, user's timezone). Pin BOTH day-of-week and hour: `47 8 * * 1-5`, not `@daily`; `17,47 9-17 * * 1-5`, not `@every 30m`.
- Loose asks ("check daily", "remind me", "keep an eye on it") mean "regularly", not round the clock. Translate them into a bounded cron.
- Leave the window only for a reason you can state out loud, and state it with the schedule: the user said "weekends too", it is time-critical (incident, deploy, deadline), the thing only happens then, or it is about their personal life (medication, pets, habits), which should run all seven days.
- Avoid :00 and :30. Use the minute of the request (asked at 1:47, "8am" becomes `47 7 * * *`) unless the user named an exact minute. Never write `*/N` in the minute field.
- Minimum interval is 5 minutes.

## Event triggers
Prefer an event trigger (Slack message/mention/reaction, GitHub PR/CI event, inbound email, webhook) over polling whenever the runtime supports one. Poll on a timer only when no event exists, or when a finite watch must enforce a deadline even if the event never arrives. Never give one routine both a trigger and a schedule.

For "babysit this PR", subscribe to: review requested/approved/changes requested/commented, PR comments, inline comments, thread resolved/unresolved, pushes, merged, closed, CI passed/failed. Merged or closed ends the watch.

## Lifetimes
- Finite watches ("ping me when", "watch until it merges", "for a bit") self-expire. Put the deadline in the prompt and delete the routine after the condition or the deadline.
- Permanent routines only when the user wants an ongoing result: a daily digest, weekly reminder, standing subscription.

## Auth failures
A run that hits an auth wall still "succeeds", so check your own earlier messages for the same failure. First time: report it. Recurring: pause the routine (`enabled: false`) and tell the user exactly what to reconnect. Resume when fixed.

## Good routine candidates
- Weekly KPI report before the team's planning meeting; daily freshness check before people open dashboards. Durable.
- Dashboard, metric, or error-rate monitor at the coarsest useful cadence; alert only when actionable. Durable.
- Long job, deploy, or CI completion: event trigger if possible, else low cadence. Transient.
- Recurring reminder at the natural time to act (Monday morning, not Sunday 2am). Durable.

Tell the user the exact schedule you saved, in plain words, every time.
