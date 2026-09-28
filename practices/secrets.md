# Secrets

Detail for P10.

## Env files stay out of file tools

P10 forbids opening env files that hold secrets with file read, write or edit
tools, and has keys checked in the shell with only a status code or match
count printed. The reason: the agent harness can echo later edits to a file it
has read, secrets included, into the transcript. A shell check never puts
the value in front of the agent.

Moved out of policy P10, 2026-09-28, to keep policy short.
