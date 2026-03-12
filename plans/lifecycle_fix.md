# Plan: task/attempt lifecycle fix for runner crashes

## Goal

Fix the task-attempt lifecycle so the framework never leaves a task in `in_progress` after its current attempt has already finished.

This should prevent the runner from terminating on invalid orchestrator decisions caused by stale task state, like the failure just observed in `../capacity/.aftk/`.

## Incident summary

### What happened

The latest persisted run sequence ended at:

- `run-0016` — worker completed
- `run-0017` — orchestrator completed

No subsequent worker run was created.
The process terminated after `run-0017`, during runner-side decision validation.

### Concrete evidence

From `../capacity/.aftk/runs/run-0017/result.json`:

- the orchestrator selected `task-0006`

From `../capacity/.aftk/runs/run-0017/messages.json` and `../capacity/.aftk/tasks/state.json` at that time:

- `task-0006` was still marked `in_progress`
- `task-0007` was also still marked `in_progress`
- there were `0` ready tasks

From the attempt records:

- `../capacity/.aftk/tasks/attempts/attempt-0004.json`
  - `task_id = task-0006`
  - `status = partial`
- `../capacity/.aftk/tasks/attempts/attempt-0005.json`
  - `task_id = task-0007`
  - `status = partial`

So both attempts had already finished, but both tasks were still `in_progress`.

Re-validating `run-0017`'s decision against the current state reproduces the runner exception exactly:

- `RunnerDecisionError: selected task is not ready after proposed changes: task-0006`

## Root cause

## 1. `finish_attempt()` records attempt completion but does not release the task

Current behavior in `aftk/tasks/service.py`:

- `claim_task(...)`
  - sets the task status to `in_progress`
  - sets `current_attempt_id`
- `finish_attempt(...)`
  - writes the finished attempt record
  - appends an `ATTEMPT_FINISHED` event
  - **does not mutate the task graph**

This behavior is currently intentional and is codified by:

- `tests/python/test_framework_tasks.py`
- `test_finish_attempt_records_attempt_without_direct_graph_mutation`

That test explicitly expects:

- the attempt to become `completed`
- while the task itself remains `in_progress`

## 2. The runner depends on the orchestrator to clean up task state afterward

Current runner flow in `aftk/runner.py`:

1. claim task
2. run worker
3. call `finish_attempt(...)`
4. save `last_worker_report`
5. next iteration: run orchestrator
6. expect orchestrator to patch task statuses appropriately

That means there is a window where:

- the attempt is finished
- the task is still `in_progress`
- the state shown to the orchestrator is already stale

## 3. That stale state can cause invalid decisions and top-level termination

In the observed failure:

- the orchestrator saw `task-0006` as `in_progress`
- nevertheless selected it
- runner validation rejected the selection because the task was not ready
- the exception happened at runner level, not inside an agent run
- so the whole CLI process terminated without a new failed run record

## Problem statement

The framework currently allows an impossible scheduler state:

- `TaskAttempt.status != RUNNING`
- while the owning `Task.status == IN_PROGRESS`
- and `Task.current_attempt_id` still points at that finished attempt

That mismatch is the lifecycle bug.

## Desired invariant

After this fix, the framework should enforce:

1. a task may be `in_progress` **only** while its current attempt exists and is `running`
2. once an attempt reaches a terminal status (`completed`, `partial`, `blocked`, `failed`), the task must no longer remain `in_progress`
3. the orchestrator should never be asked to reason over a task snapshot containing stale finished attempts as active work
4. startup recovery should handle both:
   - missing attempt records
   - attempts still marked `running` after process interruption
   - tasks whose attempt is already finished but whose task state was not released

## Design decision

Keep the separation between:

- attempt records as execution history
- task graph as planner-visible state

But stop relying on the orchestrator to repair stale `in_progress` bookkeeping.

The runner/task service should automatically reconcile task state when an attempt finishes.

In other words:

- orchestrator should decide **what to do next**
- runner/task service should maintain **basic lifecycle consistency**

## Proposed fix

## Phase 1: introduce explicit task-release reconciliation

Add a new task-service operation, conceptually something like:

- `release_task_after_attempt(...)`
- or `reconcile_finished_attempt(...)`

This method should:

- load the task and its current attempt
- verify the attempt is terminal
- clear `current_attempt_id`
- transition the task out of `in_progress`
- append task/attempt lifecycle events
- save the updated state atomically

This should be called by the runner immediately after `finish_attempt(...)`.

## Phase 2: define terminal-attempt → task-state mapping

Recommended default mapping:

- `TaskAttemptStatus.COMPLETED`
  - task becomes `completed`
- `TaskAttemptStatus.PARTIAL`
  - task becomes `ready` or `planned` via normal dependency normalization
- `TaskAttemptStatus.BLOCKED`
  - task becomes `blocked`
  - if a `WorkerReport` exists, persist its blockers into the task
- `TaskAttemptStatus.FAILED`
  - task becomes `failed` by default
  - keep enough notes/context so the orchestrator may explicitly reopen it later if desired

Why this mapping:

- it removes stale `in_progress`
- it makes the task graph reflect actual execution results
- it still lets the orchestrator add follow-up tasks, reprioritize, reopen, or patch later

### Note on policy choice

The only debatable mapping is `failed`.
Alternative behavior would be to return failed tasks to `planned`/`ready` so the orchestrator can retry them more easily.

Recommendation:

- use `failed` as the default lifecycle outcome
- allow orchestrator patches to reopen a task explicitly when appropriate

That keeps the graph honest while preserving flexibility.

## Phase 3: use worker report data when available

The runner already has `WorkerReport` after a successful worker run.
Use it when reconciling the task.

Recommended behavior:

- `completed`
  - mark task `completed`
  - optionally append a note summarizing worker evidence/handoff
- `partial`
  - mark task `ready`/`planned`
  - append summary note
- `blocked`
  - mark task `blocked`
  - persist `report.blockers`
- `failed`
  - mark task `failed`
  - append summary note

For the exception path where no `WorkerReport` exists:

- finish the attempt as `failed`
- release the task from `in_progress`
- mark the task `failed` with a note summarizing the exception

## Phase 4: reconcile stale tasks at runner startup too

Extend startup recovery so it handles not only interrupted runs, but also inconsistent finished-attempt state.

Today `recover_interrupted_tasks(...)` only requeues tasks that are still `in_progress`, regardless of whether the corresponding attempt record is missing or still `running`.

Add logic so that if:

- task is `in_progress`
- current attempt exists
- attempt status is terminal

then the task is reconciled immediately instead of being left stale.

This provides defense in depth for:

- older buggy state already on disk
- crashes between attempt finalization and task release
- manual interruption in awkward windows

## Phase 5: strengthen validation

Add a service-level consistency check that rejects stale active-task state.

Because `TaskState` itself does not contain attempt bodies, this should live in `TaskService`, not in the pure Pydantic model.

Suggested rule:

- if a task is `in_progress` and its `current_attempt_id` refers to a stored attempt whose status is not `running`, raise a lifecycle consistency error

Use this in:

- runner startup
- before orchestrator invocation
- before claiming a new task

This ensures the bug cannot silently recur.

## Why this is preferable to the status quo

Without this fix:

- finished attempts leave stale `in_progress` tasks behind
- orchestrator prompts are given inconsistent state
- runner validation can fail after an otherwise successful orchestrator run
- the top-level process dies without a new failed run record
- the system depends on the orchestrator to do bookkeeping cleanup it should not own

With this fix:

- task snapshots shown to the orchestrator are lifecycle-consistent
- runner validation becomes less fragile
- tasks become schedulable again after partial work
- blocked/failed/completed outcomes are reflected directly in persistent state

## Concrete code areas to change

Primary targets:

- `aftk/tasks/service.py`
  - add reconciliation/release method(s)
  - extend recovery/validation logic
- `aftk/runner.py`
  - invoke reconciliation after `finish_attempt(...)`
  - invoke reconciliation in the exception path too
- `tests/python/test_framework_tasks.py`
  - replace the current expectation that finished attempts leave tasks `in_progress`
  - add new lifecycle tests
- `tests/python/test_framework_runner.py`
  - add regression coverage for the exact `run-0017`-style failure mode

Possible secondary targets:

- `aftk/tasks/models.py`
  - only if a new event kind or helper enum is needed
- `aftk/tasks/store.py`
  - likely no schema changes needed

## Test plan

## 1. Update the existing task-service lifecycle test

Replace the old behavior asserted by:

- `test_finish_attempt_records_attempt_without_direct_graph_mutation`

New expected behavior:

- after finishing an attempt and reconciling it
- the task is no longer `in_progress`
- `current_attempt_id` is cleared
- the task status reflects the attempt outcome mapping

## 2. Add task-service regression tests for each attempt outcome

Add focused tests for:

- completed attempt -> task completed
- partial attempt -> task re-ready/re-planned
- blocked attempt -> task blocked with blockers
- failed attempt -> task failed

## 3. Add startup-recovery regression for stale finished attempts

Construct on-disk state where:

- task says `in_progress`
- attempt record exists and is `partial` or `failed`

Verify startup reconciliation repairs it automatically.

## 4. Add runner regression for the exact observed failure

Simulate the sequence:

- worker finishes
- task remains stale `in_progress`
- orchestrator selects that task

Then verify the new lifecycle fix prevents the stale snapshot from ever reaching that failure mode.

Success condition:

- either the task is already reconciled before orchestrator runs
- or the runner rejects/reconciles stale state before decision validation
- and no top-level `RunnerDecisionError` occurs for this cause

## 5. Add exception-path test

Simulate a worker exception after task claim.
Verify that:

- attempt is finished as `failed`
- task is released from `in_progress`
- rerunning the framework does not leave the task stuck active forever

## Open questions

## 1. Should `failed` attempts mark tasks `failed` or requeue them?

Recommendation:

- default to `failed`
- let orchestrator explicitly reopen when wanted

## 2. Should `completed` be automatic, or should orchestrator still be required to mark completion?

Recommendation:

- automatic `completed`
- orchestrator remains free to add follow-up tasks and notes afterward

This matches the semantic meaning of a worker report saying the assigned task is completed.

## 3. How much worker-report detail should be copied into task notes automatically?

Recommendation:

- append a short summary note only
- keep detailed evidence in run artifacts
- avoid duplicating full transcripts into task state

## Acceptance criteria

This work is complete when:

1. a task cannot remain `in_progress` after its current attempt has finished
2. the runner no longer crashes in the `run-0017` scenario
3. orchestrator snapshots do not contain stale finished attempts as active tasks
4. startup recovery repairs old inconsistent states left by previous buggy runs
5. task/attempt lifecycle tests reflect the new invariant and pass
6. the next `../capacity`-style run can continue past a finished worker attempt without manual intervention

## Suggested implementation order

1. add task-release reconciliation in `TaskService`
2. call it from `FrameworkRunner` after both successful and failed worker attempts
3. extend startup recovery to repair stale finished attempts
4. add service-level consistency checks
5. update/add task and runner regression tests
6. optionally improve top-level CLI failure logging once the lifecycle bug is fixed
