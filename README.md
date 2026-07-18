# Awesome Agent Skills

Battle-tested skills for AI coding agents (Claude Code, Codex, OpenClaw, ...).
Each folder is one skill: a `SKILL.md` playbook plus optional `scripts/` and `references/`.

## Skills

| Skill | What it does |
|---|---|
| [macos-disk-cleanup](macos-disk-cleanup/SKILL.md) | Audit macOS disk usage, tier findings by deletion safety, reclaim space only after per-tier approval. Never deletes on its own. |

## Quick use — paste a link

Copy the skill's `SKILL.md` link and tell your agent to follow it:

```
Read and follow this skill, then help me free up disk space:
https://raw.githubusercontent.com/eav-solution/awesome-agent-skills/main/macos-disk-cleanup/SKILL.md
```

Works in any agent that can fetch URLs. For bundled `scripts/` and `references/`, the agent can fetch them from the same base URL — or install locally (below) so everything is on disk.

## Install — copy the folder

```bash
git clone https://github.com/eav-solution/awesome-agent-skills
```

Then copy the skill folder into your agent's skills directory:

| Agent | Destination |
|---|---|
| Claude Code (global) | `~/.claude/skills/<skill-name>/` |
| Claude Code (per project) | `<repo>/.claude/skills/<skill-name>/` |
| Codex | `~/.codex/skills/<skill-name>/` |
| OpenClaw | `~/.openclaw/skills/<skill-name>/` |

```bash
cp -R awesome-agent-skills/macos-disk-cleanup ~/.claude/skills/
```

Restart your session — the agent picks the skill up automatically and triggers it when the task matches (e.g. "my disk is full").

## Layout

```
<skill-name>/
├── SKILL.md          # the playbook (frontmatter: name + trigger description)
├── scripts/          # executable helpers the skill calls
├── references/       # deep-dive docs loaded on demand
└── evals/            # test prompts + assertions used to benchmark the skill
```
