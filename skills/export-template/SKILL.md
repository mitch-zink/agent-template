---
name: export-template
description: >-
  Create a shareable copy of this agent's setup. Use when the user wants to
  share, export, or fork this agent.
---
# Export as a template

A template is this workspace minus everything personal. The output is a new folder (or repo) laid out exactly like this one.

## 1. Read, in order
Memory (`MEMORY.md`, `AGENTS.md` conventions, `TOOLS.md`), skills, routines (`cron.d/`), config. After each, send one short line with counts and names ("Read my routines: standup-summary, pr-babysitter."). Don't paste contents.

Skip daily notes (`memory/YYYY-MM-DD.md`), `memory/people/`, `memory/groups/`, `dreams/`, `goals/`, `USER.md` content. Those are the user, not the workflow.

## 2. Choose
Two separate decisions:
- **Audience:** team (can keep team process, repo names, how the team works) or public (generalize anything company-internal, keep the workflow).
- **Personal vs shared:** leave out the user's private stuff either way.

Always remove: secrets, credentials, tokens, people's names, emails, phone numbers, addresses, account numbers, private links, trade secrets.

Judge each item on its own. A convention sitting next to a secret is still a convention: take the sensitive bit out and keep the rest ("send Meg the Monday staffing plan" becomes "send your staffing lead the Monday staffing plan"). Drop an item only when the sensitive part is the whole item. "The team channel", "the watched repo" are already generic; keep them.

Config: keep the shape, replace every value that identifies the user or authenticates anything with a placeholder.

## 3. Getting started
Rewrite `BOOTSTRAP.md` from this agent's real setup, generalized: one line on what the agent does, then the setup questions whose answers made it work (which channels, repos, services to connect; what to be called; how the new owner works), asked one at a time, then what to do with the answers (fill `USER.md`, write memories, enable routines). Written as the new agent talking to its new owner. Short.

## 4. Ship
One line on what's kept vs left out ("Keeping 3 memories, 2 skills, 4 routines; leaving out personal memories and people pages."). Then write the template. If anything was a gray area (possible trade secret, thin evidence a skill is needed), add one short note on what you chose, without quoting the sensitive part.

Before calling it done, grep the output for emails, phone numbers, `sk-`/`ghp_`/`xox` style tokens, and the user's name.
