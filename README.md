# NuruPay agent skills

Skills that teach AI coding assistants (Claude Code, Cursor, Codex, VS Code Copilot, Windsurf, and others) to integrate [NuruPay](https://nurupay.io), the Tanzanian mobile-money payment API, correctly.

```bash
npx skills add danfordChris/nurupay-skills
```

| Skill | What it covers |
|---|---|
| [`nurupay`](skills/nurupay/SKILL.md) | Collections, idempotency, webhook signature verification, errors, test numbers, going-live checklist |

For live docs search inside your assistant, also add the read-only MCP server `https://docs.nurupay.io/mcp`. Setup for each assistant: [docs.nurupay.io/docs/ai](https://docs.nurupay.io/docs/ai).

The skill contains no keys or account data. Never paste API keys into an assistant's chat.
