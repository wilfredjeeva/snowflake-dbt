#!/usr/bin/env python3
"""
validate_metadata.py
====================
Governance metadata validation script for dbt models.

Runs BEFORE dbt build in the CI/CD pipeline (test-deploy.yml).
Fails with exit code 1 if any model YAML violates governance standards.

Rules enforced:
  1. Every model must have a non-empty 'description'
  2. Every model must have at least one 'domain:*' tag
  3. Every model must have 'meta.owner' defined
  4. Every model must have 'meta.data_classification' defined

Valid domain tags  : domain:airbnb, domain:finance, domain:operations, etc.
Valid data_classification values: internal, confidential, public, restricted
"""

import os
import sys
import glob
import yaml

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
MODELS_DIR = os.path.join(os.path.dirname(__file__), "..", "datahub_refinery", "models")
VALID_CLASSIFICATIONS = {"internal", "confidential", "public", "restricted"}

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def find_model_yamls(models_dir: str) -> list[str]:
    """Find all model schema YAML files (exclude sources)."""
    pattern = os.path.join(models_dir, "**", "*.yml")
    model_files: list[str] = []
    for path in glob.glob(pattern, recursive=True):
        basename = os.path.basename(path)
        if not basename.startswith("_"):
            model_files.append(path)
            continue
        # For files starting with "_", only include if they contain "models"
        with open(path, encoding="utf-8") as fh:
            if "models" in fh.read():
                model_files.append(path)
    return model_files


def validate_model(model: dict, yaml_file: str) -> list[str]:
    """Validate a single model entry. Returns list of violations."""
    violations = []
    name = model.get("name", "<unnamed>")
    prefix = f"[{os.path.basename(yaml_file)}] model '{name}'"

    # Rule 1: description must be non-empty
    description = model.get("description", "").strip()
    if not description:
        violations.append(f"{prefix}: missing or empty 'description'")

    # Rule 2: at least one domain:* tag required
    config = model.get("config", {}) or {}
    tags = config.get("tags", []) or []
    domain_tags = [t for t in tags if t.startswith("domain:")]
    if not domain_tags:
        violations.append(
            f"{prefix}: missing domain tag — add e.g. 'domain:airbnb' to config.tags"
        )

    # Rule 3: meta.owner required
    meta = config.get("meta", {}) or {}
    if not meta.get("owner", "").strip():
        violations.append(
            f"{prefix}: missing 'meta.owner' — add e.g. owner: 'data-engineering'"
        )

    # Rule 4: meta.data_classification required and must be a known value
    classification = meta.get("data_classification", "").strip().lower()
    if not classification:
        violations.append(
            f"{prefix}: missing 'meta.data_classification' "
            f"— valid values: {sorted(VALID_CLASSIFICATIONS)}"
        )
    elif classification not in VALID_CLASSIFICATIONS:
        violations.append(
            f"{prefix}: invalid data_classification '{classification}' "
            f"— valid values: {sorted(VALID_CLASSIFICATIONS)}"
        )

    return violations


def validate_yaml_file(yaml_file: str) -> list[str]:
    """Parse a YAML schema file and validate all models within it."""
    violations = []
    try:
        with open(yaml_file, "r", encoding="utf-8") as f:
            content = yaml.safe_load(f)
    except yaml.YAMLError as e:
        return [f"[{yaml_file}]: YAML parse error — {e}"]

    if not content or "models" not in content:
        return []  # sources-only file, skip

    for model in content.get("models", []):
        violations.extend(validate_model(model, yaml_file))

    return violations


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("dbt Governance Metadata Validation")
    print("=" * 60)

    yaml_files = find_model_yamls(MODELS_DIR)
    if not yaml_files:
        print("No model YAML files found — nothing to validate.")
        sys.exit(0)

    print(f"Scanning {len(yaml_files)} model YAML file(s)...\n")

    all_violations = []
    for yaml_file in sorted(yaml_files):
        violations = validate_yaml_file(yaml_file)
        if violations:
            all_violations.extend(violations)
        else:
            rel = os.path.relpath(yaml_file, MODELS_DIR)
            print(f"  ✅ {rel}")

    print()

    if all_violations:
        print("❌ GOVERNANCE VALIDATION FAILED")
        print("-" * 60)
        for v in all_violations:
            print(f"  ✗ {v}")
        print()
        print(f"Total violations: {len(all_violations)}")
        print("Fix the above issues before this PR can be promoted.")
        sys.exit(1)
    else:
        print("✅ All models passed governance metadata validation.")
        sys.exit(0)


if __name__ == "__main__":
    main()
