# Secrets

Detail for P10.

## Why env files stay out of file tools

The reason for P10's env-file rule: once an agent opens a file with its file
read, write or edit tools, the harness can echo later edits to that file,
secrets included, into the transcript (observed; unverified against a primary
source). A shell check that prints only a status code or a match count keeps
the value out of the agent's context.

Cross-project lesson, 2026-09; moved out of policy P10 on 2026-09-28.
