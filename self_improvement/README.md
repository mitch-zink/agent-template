# How you evolve

Background passes that run between conversations. Same agent, same user. Each is driven by a routine in `cron.d/`; enable the ones your runtime can afford.

| Pass | Cadence | What it changes |
|---|---|---|
| **Memory upkeep** | hourly when there's new conversation | Consolidates new signal into `MEMORY.md`. Newer claims supersede older; daily notes keep the trail. Doesn't replace writing things down in-session. |
| **Relationships** | hourly-daily | One page per stakeholder and partner team in `memory/people/`, `memory/groups/`: what they own, what they ask for, how they like answers. |
| **Studying** | nightly | Researches briefings for active `goals/`, adds progress nudges, occasionally proposes a goal the user implied but never stated. |
| **Idea curation** | daily | Fresh suggestions from the user's real context, each rated on feasibility, personal fit, novelty, then ranked. Only the top few surface. |
| **Dreaming** | nightly | Reviews recent conversations: what worked, what ruptured, who this user is becoming. Writes `dreams/YYYY-MM-DD.md`, a repair note for anything that needs mending, and an updated "how to act for this user" synthesis. |
| **Skill review** | weekly | Recurring workflows become skills; existing skills are audited against recent runs; ones that measurably don't help are retired. |
| **Quiet-moment pass** | after a long conversation goes quiet, a few times a day max | One bounded sweep to internalize what just happened. |

## Rules for every pass
- **Record the why.** Each change notes what was learned and the evidence, so "why did you suggest that?" has a real answer, not one reconstructed from the result.
- **Queued is not delivered.** A run that finished or a message that was emitted doesn't prove the user received it. Say what the records establish and where the gaps are.
- **Stage before you overwrite.** Write proposed changes to `self_improvement/staging/<area>/` first when a pass would rewrite a file the user edits by hand (`SOUL.md`, `USER.md`). Apply on the next main session after a glance.
- **Silent by default.** Passes don't message the user. Anything worth saying goes to the next digest via `MEMORY.md` Commitments or `PROACTIVE_PREFERENCES.md` rules.
- **Archive objectives.** Each pass can keep `self_improvement/objectives/<pass>/CURRENT.md` (what it's optimizing for now) and move the old one to `archive/<timestamp>.CURRENT.md` when it changes.
