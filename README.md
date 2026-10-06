# NuruPay for AI coding assistants

Teach your AI coding assistant to integrate [NuruPay](https://nurupay.io), the Tanzanian mobile-money payment API, correctly: keys on the server, an `Idempotency-Key` on every `POST`, only `succeeded` means paid, verified webhook signatures, and the test numbers.

Works with Claude Code, Codex, Cursor, GitHub Copilot, Gemini CLI, Windsurf, opencode, and other assistants that read `AGENTS.md` or agent skills.

## Install

### Everything at once (recommended)

Writes the NuruPay rules to the instruction files every assistant reads, and installs the `nurupay` skill.

**This project** (run in your project folder; commit the files to share them with your team):

```bash
curl -fsSL https://raw.githubusercontent.com/danfordChris/nurupay-skills/main/install.sh | sh
```

**Global** (every project on this computer):

```bash
curl -fsSL https://raw.githubusercontent.com/danfordChris/nurupay-skills/main/install.sh | sh -s -- --global
```

| Scope | Files |
|---|---|
| Project | `AGENTS.md` gets a NuruPay section. `CLAUDE.md` and `GEMINI.md` load it with `@AGENTS.md`, so Claude Code and Gemini CLI read the same rules. The skill goes into `.agents/skills/` and each assistant's skills folder. |
| Global | The NuruPay section goes into `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md`, and Windsurf's global rules, for the assistants you have installed. The skill is installed for your user. |

The script only adds, replaces, or removes the section between `<!-- nurupay:start -->` and `<!-- nurupay:end -->`. Your own content stays as it is. If `CLAUDE.md` is already a symlink to `AGENTS.md`, it is left alone. Re-run it to update.

Options: `--dir PATH` (project folder), `--no-skill` (instruction files only), `--uninstall` (remove everything it added; add `--global` for the global install). Read [`install.sh`](install.sh) before running it if you prefer.

### Skill only

```bash
npx skills add danfordChris/nurupay-skills        # this project
npx skills add danfordChris/nurupay-skills -g     # global
```

| Skill | What it covers |
|---|---|
| [`nurupay`](skills/nurupay/SKILL.md) | Collections, idempotency, webhook signature verification, errors, test numbers, going-live checklist |

### Docs search (MCP)

Add the read-only MCP server `https://docs.nurupay.io/mcp` so your assistant can search the docs and read the OpenAPI spec. Setup for each assistant: [docs.nurupay.io/docs/ai](https://docs.nurupay.io/docs/ai).

Nothing here contains keys or account data. Never paste API keys into an assistant's chat.
