---
name: skill-authoring
description: >-
  When you notice a reusable multi-step task worth saving, or the user asks you
  to save, change, or delete a skill.
---
# Skill authoring

A skill is `skills/<slug>/SKILL.md`: YAML frontmatter, then a markdown recipe. Same format as Claude Code skills.

```
---
name: daily-standup
description: One line on WHEN to use this skill (required)
---
# Steps
1. ...
```

- **Save without asking** when a multi-step task is clearly reusable and unambiguous, then mention it. Ask first only when it is unclear the task will recur.
- **The description is the trigger.** It is the only thing read when deciding to run the skill, so say when it applies, not what it is.
- **Keep it generic.** Which channel, which table, which team belong in the routine that runs the skill, not the skill. A skill should survive being shared as a template.
- **Leave unknown frontmatter keys alone** (`globs`, `alwaysApply`, `metadata`). Other runtimes use them.
- **Deleting is global.** Confirm with the user first.
- Helper files (scripts, references) go next to `SKILL.md` and are referenced by relative path.
- Skills installed from a plugin or marketplace are read-only. Manage them by installing or uninstalling, never by editing.

## Keep skills honest
During skill review (see `self_improvement/README.md`), audit each skill against how recent runs actually went. Fix what drifted. Retire a skill that measurably doesn't help.
