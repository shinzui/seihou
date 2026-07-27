---
id: 75
slug: adopt-generic-lens-record-conventions-before-1-0-0-0
title: "Adopt generic-lens record conventions before 1.0.0.0"
kind: exec-plan
created_at: 2026-07-27T17:49:55Z
---

# Adopt generic-lens record conventions before 1.0.0.0

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Explain in a few sentences what someone gains after this change and how they can see it
working. State the user-visible behavior you will enable.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Example incomplete step.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: ...
  Rationale: ...
  Date: ...


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

Describe the current state relevant to this task as if the reader knows nothing. Name the
key files and modules by full path. Define any non-obvious term you will use. Do not refer
to prior plans unless they are checked into the repository, in which case reference them by
path. Follow the skill's ADR.md workflow: scan local filenames and headings, read only ADRs
relevant to this work, and summarize them here with repository-relative links. Cite a
cross-repository ADR only with the exact canonical handle returned by Mori. If no relevant
ADR exists, say so.


## Plan of Work

Describe, in prose, the sequence of edits and additions. For each edit, name the file and
location (function, module) and what to insert or change. Keep it concrete and minimal.

Break into milestones if the work spans multiple independent phases. Each milestone must be
independently verifiable. Introduce each milestone with a brief paragraph: scope, what will
exist at the end, commands to run, acceptance criteria.


## Concrete Steps

State the exact commands to run and where to run them (working directory). When a command
generates output, show a short expected transcript so the reader can compare. This section
must be updated as work proceeds.


## Validation and Acceptance

Describe how to exercise the system and what to observe. Phrase acceptance as behavior with
specific inputs and outputs. If tests are involved, name the exact test commands and expected
results. Show that the change is effective beyond compilation.


## Idempotence and Recovery

If steps can be repeated safely, say so. If a step is risky, provide a safe retry or
rollback path.


## Interfaces and Dependencies

Name the libraries, modules, and services to use and why. Specify the types, interfaces, and
function signatures that must exist at the end of each milestone. Use full module paths.
