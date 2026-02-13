"""E2E: Secret substitution through the detection chain."""

from __future__ import annotations

import os

import pytest

from tests.test_e2e.conftest import (
    BASE_PATH,
    find_one_model_path,
    make_config,
    run_detect_chain,
)


class TestSecretChain:

    def test_secret_in_model_path_resolved(self):
        """Secret token in object_weights gets resolved before detection."""
        weights, config, labels = find_one_model_path()

        ml_seq = {
            "general": {"model_sequence": "object"},
            "object": {
                "general": {"pattern": ".*"},
                "sequence": [{
                    "name": "secret-test",
                    # Use the !TOKEN secret syntax (template_fill lowercases keys)
                    "object_weights": "!MODEL_WEIGHTS",
                    "object_config": config,
                    "object_labels": labels,
                    "object_framework": "opencv",
                    "object_processor": "cpu",
                    "object_min_confidence": 0.3,
                }],
            },
        }

        # template_fill lowercases secret keys during lookup
        secrets = {"model_weights": weights}
        config_path, secrets_path = make_config(ml_seq, secrets=secrets)
        try:
            matched_data, output, _ = run_detect_chain(
                config_path, secrets_path=secrets_path
            )
            assert len(matched_data["labels"]) > 0, "Detection should succeed with resolved secret"
            assert output, "Expected non-empty output"
        finally:
            os.unlink(config_path)
            if secrets_path:
                os.unlink(secrets_path)

    def test_secret_in_general_fields_resolved(self):
        """Secret tokens in general section (e.g. user/password) resolve correctly."""
        weights, config, labels = find_one_model_path()

        ml_seq = {
            "general": {"model_sequence": "object"},
            "object": {
                "general": {"pattern": ".*"},
                "sequence": [{
                    "name": "secret-general-test",
                    "object_weights": weights,
                    "object_config": config,
                    "object_labels": labels,
                    "object_framework": "opencv",
                    "object_processor": "cpu",
                    "object_min_confidence": 0.3,
                }],
            },
        }

        secrets = {
            "ZM_USER": "testuser",
            "ZM_PASSWORD": "testpass",
        }
        config_path, secrets_path = make_config(
            ml_seq,
            secrets=secrets,
            general_overrides={"user": "!ZM_USER", "password": "!ZM_PASSWORD"},
        )
        try:
            _, _, g_config = run_detect_chain(config_path, secrets_path=secrets_path)
            assert g_config["user"] == "testuser"
            assert g_config["password"] == "testpass"
        finally:
            os.unlink(config_path)
            if secrets_path:
                os.unlink(secrets_path)
