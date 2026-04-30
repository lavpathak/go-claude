# /mode — Switch Engineer Mode

Set how Claude paces, explains, and scopes work across every command and
skill. The mode is stored in `CLAUDE.md` as the `Current mode` field.

## Usage

```
/mode beginner
/mode senior
/mode staff
/mode             # with no argument: report the current mode
```

## Process

1. **Read `CLAUDE.md`** and locate the line `**Current mode: \`<value>\`**`
   under the `## Engineer Mode` section.

2. **If `$ARGUMENTS` is empty**, report the current mode and a one-line
   summary of how it changes Claude's behavior. Stop.

3. **If `$ARGUMENTS` is set**, validate it is one of:
   `beginner`, `senior`, `staff`. If not, list the valid values and stop —
   do not modify the file.

4. **Edit `CLAUDE.md`**: replace the existing `**Current mode: \`<old>\`**`
   line with `**Current mode: \`<new>\`**`. Do not touch any other content.

5. **Confirm the switch** with a short summary of what changes:

   - **beginner** → Socratic teaching, idiom explanations, small phased
     scope, frequent check-ins.
   - **senior** → Peer tone, decisions narrated not idioms, scope sized to
     one reviewable sitting, no mandatory check-ins mid-task.
   - **staff** → Design-first conversation, idiom commentary skipped, phase
     plans with rollout/rollback considerations on non-trivial work.

6. **Remind** the developer that the mode persists across sessions because
   it lives in `CLAUDE.md`, and that they can switch back at any time.

## Rules

- This command only ever edits the `Current mode` line in `CLAUDE.md`. It
  never edits skills, other commands, or project code.
- If the `Current mode` line is missing from `CLAUDE.md`, do not silently
  add it. Tell the developer the file looks malformed and ask whether to
  restore the `## Engineer Mode` section.

$ARGUMENTS: `beginner`, `senior`, `staff`, or empty to report current mode
