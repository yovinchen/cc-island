# Cursor Hooks — Gap Analysis

> Docs: https://cursor.com/docs/hooks

## Implemented Events

| Cursor Event | Mapped To | Tool | Has Response |
|---|---|---|---|
| `beforeSubmitPrompt` | `UserPromptSubmit` | — | No |
| `beforeShellExecution` | `PermissionRequest` | `Bash` | Yes: `{continue, permission}` |
| `beforeMCPExecution` | `PermissionRequest` | MCP tool name | Yes: `{continue, permission}` |
| `beforeReadFile` | `PreToolUse` | `Read` | No (auto-continue) |
| `afterFileEdit` | `PostToolUse` | `Edit` | No |
| `stop` | `Stop` | — | No |

## Key Differences from Claude Code

| Feature | Claude Code | Cursor |
|---|---|---|
| Config path | `~/.claude/settings.json` | `~/.cursor/hooks.json` |
| Config format | Nested `{matcher, hooks: [{type, command}]}` | Flat `{"version": 1, "hooks": {"event": [{"command": "..."}]}}` |
| Event names | PascalCase (`PreToolUse`) | camelCase (`beforeShellExecution`) |
| Permission model | Dedicated `PermissionRequest` event | `before*` hooks return `{continue: bool}` |
| Session ID | `session_id` in every event | `conversation_id` only in `beforeSubmitPrompt` |
| Response format | `{hookSpecificOutput: {decision: {behavior}}}` | `{continue: bool, permission?: "allow\|deny\|ask"}` |
| Always Allow | `updatedPermissions.addRules` | `{permission: "allow"}` |
| Bypass mode | `updatedPermissions.setMode: "bypassPermissions"` | Not supported |

## Unimplemented Features

### 1. `userMessage` / `agentMessage` in Response
Cursor's `beforeShellExecution` and `beforeMCPExecution` responses support `userMessage` and `agentMessage` fields that inject messages into the conversation. Not implemented — would require extending the approval UI to include a text input field.

### 2. `attachments` in `beforeSubmitPrompt`
The `beforeSubmitPrompt` event includes an `attachments` array with file paths and URLs. Currently ignored — could be displayed in the UI as context.

### 3. `edits` Array in `afterFileEdit`
The `afterFileEdit` event includes an `edits` array with `{old_string, new_string}` pairs showing exactly what changed. Currently only the `file_path` is extracted. Could be used for diff display in the UI.

### 4. `beforeReadFile` content
The `beforeReadFile` event includes the full `content` of the file being read. Currently ignored to avoid memory overhead. Could optionally be captured for audit logging.

### 5. Project-level hooks (`.cursor/hooks.json`)
Cursor supports both global (`~/.cursor/hooks.json`) and project-level (`.cursor/hooks.json`) hook configs. Currently only the global config is managed. Project-level hooks require per-workspace installation.

### 6. Session Continuity Across Events
Cursor only provides `conversation_id` in `beforeSubmitPrompt`. Other events have no session identifier, making it difficult to group events into the same session. Current workaround: generate IDs per-event, which may create duplicate sessions.

## Notes

- Cursor hooks are a relatively new feature (2024+), so the API may evolve
- The `version: 1` field in the config is required
- Hook commands receive JSON via stdin and write JSON to stdout
- If a hook command fails or times out, Cursor continues with default behavior
