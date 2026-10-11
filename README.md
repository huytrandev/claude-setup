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

Unbound slots use the defaults. The SessionStart hook warns about bindings to agents that do not exist.

To turn podium off for one project, set `{ "enabledPlugins": { "podium@claude-setup": false } }` in that project's `.claude/settings.json` (verified: it overrides the user-scope install).

## Workspace

Task files live in `~/.agent-work/<project>/<date-task>/` unless `workspace` is set.

## Tests

```bash
bash tests/run.sh                              # unit + static
PODIUM_SMOKE=1 bash tests/smoke/run-smoke.sh   # headless, costs tokens
```

## Requirements

bash (Git Bash on Windows) for the SessionStart hook. `jq` for running the tests.
