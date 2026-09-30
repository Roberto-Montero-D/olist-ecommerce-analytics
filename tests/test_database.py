import pytest
from sqlalchemy import URL

from src import database

ENV_KEYS = (
    "POSTGRES_HOST",
    "POSTGRES_PORT",
    "POSTGRES_DB",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
)


def clear_database_environment(monkeypatch) -> None:
    for key in ENV_KEYS:
        monkeypatch.delenv(key, raising=False)


def set_database_environment(monkeypatch) -> None:
    monkeypatch.setenv("POSTGRES_HOST", "localhost")
    monkeypatch.setenv("POSTGRES_PORT", "5432")
    monkeypatch.setenv("POSTGRES_DB", "olist")
    monkeypatch.setenv("POSTGRES_USER", "olist")
    monkeypatch.setenv("POSTGRES_PASSWORD", "p@ss:word/test")


def test_get_engine_reports_all_missing_environment_variables(monkeypatch) -> None:
    clear_database_environment(monkeypatch)

    with pytest.raises(ValueError) as exc_info:
        database.get_engine()

    message = str(exc_info.value)
    for key in ("host", "port", "database", "user", "password"):
        assert key in message


def test_get_engine_builds_sqlalchemy_url_without_connecting(monkeypatch) -> None:
    set_database_environment(monkeypatch)
    captured = {}

    def fake_create_engine(url):
        captured["url"] = url
        return object()

    monkeypatch.setattr(database, "create_engine", fake_create_engine)

    engine = database.get_engine()

    assert engine is not None
    assert isinstance(captured["url"], URL)
    assert captured["url"].drivername == "postgresql+psycopg2"
    assert captured["url"].username == "olist"
    assert captured["url"].password == "p@ss:word/test"
    assert captured["url"].host == "localhost"
    assert captured["url"].port == 5432
    assert captured["url"].database == "olist"
