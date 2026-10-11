# claude-setup

Personal Claude Code setup. Contains the **podium** plugin: a model-pinned agent team routed by a model-agnostic conductor.

## Install podium only

```bash
claude plugin marketplace add <path-or-git-url-of-this-repo>
claude plugin install podium@claude-setup
```

## Team

| Slot | Default agent | Model |
|---|---|---|
| planner | `podium:composer` | `claude-opus-5-5` |
| critic | `podium:critic` | `claude-opus-5-5` |
| builder | `podium:performer` | `claude-sonnet-5-5` |
| scout | `podium:scout` | `claude-haiku-5-5` |

## Bind project agents

Create `<repo>/.claude/team.json` (schema: `plugins/podium/schema/team.schema.json`):

```json
{
  "version": 1,
  "slots": { "planner": "my-architect", "builder": "my-senior-dev" },
  "workspace": null,
  "fallbackModel": null
}
```

`fallbackModel` is `null` (no fallback) or one of `sonnet`, `opus`, `haiku`, `fable` (the Agent tool's `model` aliases); the conductor uses it only when a pinned model is unavailable and says so. Agent frontmatter keeps full model IDs. Example: `"fallbackModel": "sonnet"`.

Unbound slots use the defaults. The SessionStart hook warns about bindings to agents that do not exist.

To turn podium off for one project, set `{ "enabledPlugins": { "podium@claude-setup": false } }` in that project's `.claude/settings.json` (verified: it overrides the user-scope install).

## Workspace

Task files live in `~/.agent-work/<project>/<date-task>/` unless `workspace` is set. When `workspace` is a relative path inside the repo, add it to `.gitignore`. On Windows, use forward slashes in `workspace` paths.

## Set up a new machine

Requirements: git, jq, Claude Code. Windows: Git for Windows (Git Bash) and PowerShell 7 (`pwsh`; Windows PowerShell 5.1 is not supported). Plugin commands ran without a login in a clean container, but sign in to Claude Code before real use.

```bash
git clone <this-repo> ~/Workspace/claude-setup
~/Workspace/claude-setup/install.sh          # macOS / Linux
pwsh ~/Workspace/claude-setup/install.ps1    # Windows
```

The installer backs up anything it replaces to `~/.claude/backups/claude-setup-<timestamp>/` and is safe to re-run. It exits 1 and prints `Failures: N` if a marketplace add or plugin install fails.
`settings.json` is copied, not linked: edit `dotfiles/settings.json` in the repo and re-run the installer to apply changes. Keys the Claude CLI writes itself (`extraKnownMarketplaces`) are preserved across re-runs.

Synced: `CLAUDE.md`, `settings.json`, `statusline-command.sh`, `hooks/guard-destructive.sh`, `skills/capturing-personal-knowledge/`.
Never synced: history, projects, sessions, credentials, caches.

## Tests

```bash
bash tests/run.sh                              # unit + static
PODIUM_SMOKE=1 bash tests/smoke/run-smoke.sh   # headless, costs tokens
bash tests/install/fresh-machine.sh            # opt-in: Docker + network, real CLI in a clean container
```

## Requirements

bash (Git Bash on Windows) for the SessionStart hook. `jq` for running the tests.
