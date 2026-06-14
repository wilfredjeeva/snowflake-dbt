## Context

**Jira ticket:** <!-- e.g. feat(DHE-123): add bronze ingest for boroughs -->

<!-- Is this a bug fix? If so, describe how to reproduce the issue. -->

---

## Intent

<!-- What changes does this PR introduce? Why are they needed? -->

---

## Changes

<!-- Tick all that apply -->

- [ ] New dbt model(s)
- [ ] Modified existing model(s)
- [ ] Schema / documentation changes (`schema.yml`)
- [ ] Macro changes
- [ ] Seed changes
- [ ] CI / workflow changes
- [ ] Script changes (`scripts/`)
- [ ] Configuration changes (`dbt_project.yml`, `packages.yml`)

---

## dbt checklist

- [ ] All new/modified models have `owner`, `tags`, and `classification` set in `schema.yml`
- [ ] New models have at least one dbt test (e.g. `not_null`, `unique`)
- [ ] No hardcoded database/schema names — using `ref()` and `source()` correctly
- [ ] `dbt parse` passes locally (or via the PR build check)

---

## Screenshots

<!-- Include if the change affects data shape, row counts, or query output. Delete if not applicable. -->

---

## Considerations

<!-- Any additional context that would help the reviewer? -->

<!-- Are there any manual steps required when merging or deploying this PR? -->

---

## Reviewer checklist

- [ ] Code is scoped to the Jira ticket — no unrelated changes
- [ ] Logic is clear and readable
- [ ] Governance metadata is complete (owner, tags, classification)
- [ ] Tests cover the new/changed logic
