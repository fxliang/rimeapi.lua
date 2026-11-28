---
name: change-plan-test-loop
description: Use for repository changes that need a reviewable implementation plan, scoped code edits, test verification, and user acceptance in a feedback loop; trigger on requests such as 变更方案、实施计划、按方案修改、测试确认, or plan/implement/test a change.
---

# Change plan, implementation, and test loop

Guide a repository change from a testable proposal through implementation and verification to explicit user acceptance. Keep the user informed at decision points and continue the loop when feedback or a test failure calls for revision.

## Workflow

### 1. Establish scope and current state

- Read applicable `AGENTS.md` files and the relevant implementation, documentation, and test instructions.
- Inspect the working tree before editing. Treat pre-existing user changes as intentional; do not overwrite, revert, or include them in the proposed change without permission.
- Identify the requested outcome, constraints, affected components, existing test commands, and any blocking unknowns.
- Prefer inspecting the repository to asking questions whose answers are already available. Ask only for information that materially changes the approach or cannot be safely inferred.

### 2. Present a testable plan

Before editing, give a concise proposal containing:

1. **Goal and scope** — what behavior will change and what is in or out of scope.
2. **Implementation steps** — the likely files/components and the order of work; label uncertain paths as provisional.
3. **Acceptance checks** — observable expected behavior and the specific automated or manual checks that can establish it.
4. **Risks or open decisions** — include only material risks, assumptions, or choices that need user input.

Make each acceptance check traceable to a requested behavior. Derive tests and expected results from requirements and repository behavior; do not invent expected outputs. If a check requires user interaction, state exactly what the user should verify.

If the user asked only for a plan, stop after presenting it. If implementation has not been authorized, ask for approval and wait before editing. A direct request to implement or apply the change is authorization: provide the concise plan, then proceed without asking for redundant approval. Resolve genuine blockers with a focused question.

### 3. Implement the agreed scope

- Make the smallest coherent set of changes that satisfies the approved plan.
- Follow repository conventions and use the existing test/build commands where practical.
- Keep implementation changes distinct from unrelated formatting, cleanup, or pre-existing edits.
- If investigation shows that the plan is materially wrong or the scope must expand, pause and explain the revised approach before making that additional change.

### 4. Run checks and close the implementation loop

- Run the checks named in the plan, plus narrowly relevant checks required by the repository.
- Report commands and actual outcomes accurately. Distinguish passed, failed, and not run; never imply a check passed if it was not executed.
- On a failure, inspect the cause, make an in-scope correction, and rerun the failing check and any affected checks. If the failure is environmental or outside scope, report the evidence and the remaining verification needed.
- Compare the final result against each acceptance check. Include any unmet check or behavior that remains uncertain.

Finish with a concise handoff: what changed, which checks ran and their results, and any remaining user-side verification. Ask the user to confirm that the outcome meets the request when acceptance depends on their environment or judgment. Do not treat a green test suite alone as user acceptance.

### 5. Continue from feedback

If the user reports a mismatch, ask for the expected and observed behavior only when it is not already clear. Update the acceptance checks if the clarified requirement changes, revise the implementation, rerun the relevant checks, and report the new result. Continue until the user confirms acceptance, asks to stop, or a clearly stated blocker prevents further progress.

## Response shape

Adapt to the user's language and keep each checkpoint compact.

**Plan checkpoint**

- Goal / scope
- Steps
- Acceptance checks
- Open question or approval request, only when needed

**Completion checkpoint**

- Changes made
- Checks run: command and outcome
- Remaining verification or known blocker
- User confirmation request, when applicable
