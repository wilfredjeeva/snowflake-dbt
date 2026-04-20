#!/usr/bin/env python3
"""
validate_metadata.py
====================
Governance metadata validation script for dbt models.

Runs BEFORE dbt build in the CI/CD pipeline.
Fails with exit code 1 if any model YAML violates governance standards.

Rules enforced:
  1. Every model must have a non-empty 'description'                        [ALL models]
  2. Every model must have at least one 'domain:*' tag                      [ALL models]
  3. Every model must have 'meta.owner' defined                             [ALL models]
  4. Every model must have 'meta.data_classification' defined               [ALL models]
  5. Every model must have at least one 'dataset:*' tag                     [GOLD & PLATINUM only]
  6. Every model must have a 'DataSet_Tag' (config.tags or config.meta)    [GOLD & PLATINUM only]

Valid domain tags             : domain:airbnb, domain:finance, domain:operations, etc.
Valid data_classification      : internal, confidential, public, restricted
dataset:* tag examples         : dataset:airbnb, dataset:addressbase, dataset:finance
DataSet_Tag examples           : DataSet_Tag:airbnb | dataset_tag: airbnb (in meta)
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

# Model path segments that identify gold & platinum tier models
GOLD_PLATINUM_SEGMENTS = {"gold", "platinum"}


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def find_model_yamls(models_dir: str) -> list[str]:
    """Find all model schema YAML files (exclude sources)."""
    pattern = os.path.join(models_dir, "**", "*.yml")
    return [
        f for f in glob.glob(pattern, recursive=True)
        if not os.path.basename(f).startswith("_") or "models" in open(f).read()
    ]


def is_gold_or_platinum(yaml_file: str) -> bool:
    """Return True if the YAML file is under a gold or platinum model directory."""
    parts = set(yaml_file.replace("\\", "/").lower().split("/"))
    return bool(parts & GOLD_PLATINUM_SEGMENTS)


def validate_model(model: dict, yaml_file: str) -> list[str]:
    """Validate a single model entry. Returns list of violations."""
    violations = []
    name = model.get("name", "<unnamed>")
    prefix = f"[{os.path.basename(yaml_file)}] model '{name}'"

    config = model.get("config", {}) or {}
    tags = config.get("tags", []) or []
    if isinstance(tags, str):
        tags = [tags]
    meta = config.get("meta", {}) or {}

    gold_platinum = is_gold_or_platinum(yaml_file)

    # ── Rule 1: description must be non-empty ─────────────────────────────────
    description = model.get("description", "").strip()
    if not description:
        violations.append(f"{prefix}: missing or empty 'description'")

    # ── Rule 2: at least one domain:* tag required (ALL models) ──────────────
    domain_tags = [t for t in tags if t.lower().startswith("domain:")]
    if not domain_tags:
        violations.append(
            f"{prefix}: missing domain tag — add e.g. 'domain:airbnb' to config.tags"
        )

    # ── Rule 3: meta.owner required (ALL models) ─────────────────────────────
    if not meta.get("owner", "").strip():
        violations.append(
            f"{prefix}: missing 'meta.owner' — add e.g. owner: 'data-engineering'"
        )

    # ── Rule 4: meta.data_classification required (ALL models) ───────────────
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

    # ── Rules 5 & 6: GOLD & PLATINUM only ────────────────────────────────────
    if gold_platinum:

        # Rule 5: at least one dataset:* tag required
        dataset_tags = [t for t in tags if t.lower().startswith("dataset:")]
        if not dataset_tags:
            violations.append(
                f"{prefix}: [GOLD/PLATINUM] missing 'dataset:*' tag "
                f"— add e.g. 'dataset:airbnb' to config.tags"
            )

        # Rule 6: DataSet_Tag required (in config.tags OR config.meta)
        dataset_tag_in_list = [t for t in tags if t.lower().startswith("dataset_tag")]
        dataset_tag_in_meta = str(meta.get("dataset_tag", "")).strip()
        if not dataset_tag_in_list and not dataset_tag_in_meta:
            violations.append(
                f"{prefix}: [GOLD/PLATINUM] missing 'DataSet_Tag' "
                f"— add e.g. 'DataSet_Tag:airbnb' to config.tags "
                f"OR dataset_tag: airbnb to config.meta"
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
            tier = " [GOLD/PLATINUM]" if is_gold_or_platinum(yaml_file) else ""
            print(f"  ✅ {rel}{tier}")

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
