from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import Field

from aftk.tasks.models import TaskArtifact, TaskModel, TaskRecord, TaskSpec

TASK_PROPOSAL_BATCH_SCHEMA_VERSION = 1
TASK_PROPOSAL_ARTIFACT_KIND = "task_proposal_batch"
TASK_PROPOSAL_REVIEW_SCHEMA_VERSION = 1
TASK_PROPOSAL_REVIEW_ARTIFACT_KIND = "task_proposal_review"


class TaskProposalDecision(StrEnum):
    """Review decisions that can be recorded for a task proposal."""

    applied = "applied"
    rejected = "rejected"


class TaskProposalStatus(StrEnum):
    """Derived review state for a proposal artifact."""

    pending = "pending"
    applied = "applied"
    rejected = "rejected"


class TaskProposalBatch(TaskModel):
    """Structured payload stored inside a task-proposal artifact."""

    schema_version: int = TASK_PROPOSAL_BATCH_SCHEMA_VERSION
    source_task_id: str = Field(min_length=1)
    rationale: str | None = None
    proposals: list[TaskSpec] = Field(min_length=1)


class TaskProposalReview(TaskModel):
    """Structured payload recording orchestrator review of a proposal."""

    schema_version: int = TASK_PROPOSAL_REVIEW_SCHEMA_VERSION
    proposal_id: str = Field(min_length=1)
    source_task_id: str = Field(min_length=1)
    decision: TaskProposalDecision
    note: str | None = None
    applied_task_ids: list[str] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)


class TaskProposalRecord(TaskModel):
    """Extracted proposal artifact together with any latest review decision."""

    proposal_id: str = Field(min_length=1)
    source_task_id: str = Field(min_length=1)
    artifact_index: int = Field(ge=1)
    created_at: datetime
    status: TaskProposalStatus = TaskProposalStatus.pending
    rationale: str | None = None
    proposals: list[TaskSpec] = Field(default_factory=list)
    artifact_metadata: dict[str, Any] = Field(default_factory=dict)
    review: TaskProposalReview | None = None
    review_created_at: datetime | None = None


def build_task_proposal_id(source_task_id: str, artifact_index: int) -> str:
    """Build a stable id for one proposal artifact on a source task."""

    return f"proposal:{source_task_id}:{artifact_index}"


def parse_task_proposal_batch(artifact: TaskArtifact) -> TaskProposalBatch | None:
    """Parse a proposal-batch artifact when the kind matches."""

    if artifact.kind != TASK_PROPOSAL_ARTIFACT_KIND:
        return None
    return TaskProposalBatch.model_validate(artifact.value)


def parse_task_proposal_review(artifact: TaskArtifact) -> TaskProposalReview | None:
    """Parse a proposal-review artifact when the kind matches."""

    if artifact.kind != TASK_PROPOSAL_REVIEW_ARTIFACT_KIND:
        return None
    return TaskProposalReview.model_validate(artifact.value)


def collect_task_proposals(tasks: Sequence[TaskRecord]) -> list[TaskProposalRecord]:
    """Collect proposal artifacts and their latest review decisions from task records."""

    proposals: dict[str, TaskProposalRecord] = {}
    for task in tasks:
        for artifact_index, artifact in enumerate(task.artifacts, start=1):
            batch = parse_task_proposal_batch(artifact)
            if batch is not None:
                proposal_id = build_task_proposal_id(task.id, artifact_index)
                proposals[proposal_id] = TaskProposalRecord(
                    proposal_id=proposal_id,
                    source_task_id=task.id,
                    artifact_index=artifact_index,
                    created_at=artifact.created_at,
                    rationale=batch.rationale,
                    proposals=[proposal.model_copy(deep=True) for proposal in batch.proposals],
                    artifact_metadata=dict(artifact.metadata),
                )
                continue

            review = parse_task_proposal_review(artifact)
            if review is None:
                continue

            record = proposals.get(review.proposal_id)
            if record is None:
                continue

            record.review = review.model_copy(deep=True)
            record.review_created_at = artifact.created_at
            if review.decision == TaskProposalDecision.applied:
                record.status = TaskProposalStatus.applied
            else:
                record.status = TaskProposalStatus.rejected

    return sorted(proposals.values(), key=lambda proposal: (proposal.created_at, proposal.proposal_id))


def get_task_proposal(tasks: Sequence[TaskRecord], proposal_id: str) -> TaskProposalRecord | None:
    """Return one collected proposal by id, if present."""

    for proposal in collect_task_proposals(tasks):
        if proposal.proposal_id == proposal_id:
            return proposal
    return None
