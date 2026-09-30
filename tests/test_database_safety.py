from unittest.mock import Mock, patch

import pytest

from src.database_safety import (
    EXPECTED_TEST_DATABASE,
    get_test_database_config,
    verify_test_database,
)


def make_connection(actual_database: str):
    cursor = Mock()
    cursor.fetchone.return_value = (actual_database,)

    context = Mock()
    context.__enter__ = Mock(return_value=cursor)
    context.__exit__ = Mock(return_value=False)

    connection = Mock()
    connection.cursor.return_value = context
    return connection


def test_guard_allows_exact_test_database():
    verify_test_database(
        make_connection(EXPECTED_TEST_DATABASE),
        EXPECTED_TEST_DATABASE,
    )


def test_guard_rejects_configured_development_database():
    with pytest.raises(RuntimeError, match="configured database"):
        verify_test_database(make_connection("olist"), "olist")


def test_guard_rejects_actual_development_database():
    with pytest.raises(RuntimeError, match="connected database"):
        verify_test_database(
            make_connection("olist"),
            EXPECTED_TEST_DATABASE,
        )


def test_guard_rejects_configuration_mismatch():
    with pytest.raises(RuntimeError, match="configured database"):
        verify_test_database(
            make_connection(EXPECTED_TEST_DATABASE),
            "olist",
        )


def test_config_rejects_missing_environment():
    with (
        patch.dict("os.environ", {}, clear=True),
        pytest.raises(RuntimeError, match="missing required database"),
    ):
        get_test_database_config()


def test_config_requires_exact_test_database():
    env = {
        "POSTGRES_HOST": "localhost",
        "POSTGRES_PORT": "5432",
        "POSTGRES_DB": "olist",
        "POSTGRES_USER": "olist",
        "POSTGRES_PASSWORD": "olist",
    }

    with (
        patch.dict("os.environ", env, clear=True),
        pytest.raises(RuntimeError, match="Expected exactly 'olist_test'"),
    ):
        get_test_database_config()
