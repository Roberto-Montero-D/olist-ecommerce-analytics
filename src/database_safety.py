import os

EXPECTED_TEST_DATABASE = "olist_test"

_REQUIRED_DATABASE_ENVIRONMENT = (
    "POSTGRES_HOST",
    "POSTGRES_PORT",
    "POSTGRES_DB",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
)


def get_test_database_config() -> dict[str, str]:
    """Return explicit configuration for destructive integration tests."""
    config = {name: os.getenv(name) for name in _REQUIRED_DATABASE_ENVIRONMENT}
    missing = [name for name, value in config.items() if not value]

    if missing:
        raise RuntimeError(
            "Refusing warehouse integration setup: missing required database "
            f"environment variables: {', '.join(missing)}"
        )

    database = config["POSTGRES_DB"]
    if database != EXPECTED_TEST_DATABASE:
        raise RuntimeError(
            "Refusing destructive warehouse integration setup: configured "
            f"database is {database!r}. Expected exactly "
            f"{EXPECTED_TEST_DATABASE!r}."
        )

    return {name: value for name, value in config.items() if value is not None}


def verify_test_database(connection, configured_database: str) -> None:
    """Verify the actual PostgreSQL target before destructive test setup."""
    if configured_database != EXPECTED_TEST_DATABASE:
        raise RuntimeError(
            "Refusing destructive warehouse integration setup: configured "
            f"database is {configured_database!r}. Expected exactly "
            f"{EXPECTED_TEST_DATABASE!r}."
        )

    with connection.cursor() as cursor:
        cursor.execute("SELECT current_database()")
        row = cursor.fetchone()

    if row is None:
        raise RuntimeError(
            "Refusing destructive warehouse integration setup: PostgreSQL "
            "did not report the connected database."
        )

    actual_database = row[0]
    if actual_database != EXPECTED_TEST_DATABASE:
        raise RuntimeError(
            "Refusing destructive warehouse integration setup: connected "
            f"database is {actual_database!r}. Expected exactly "
            f"{EXPECTED_TEST_DATABASE!r}."
        )
