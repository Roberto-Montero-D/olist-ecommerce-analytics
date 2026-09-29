import os

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine


load_dotenv()

def get_engine() -> Engine:
    config = {
        "host": os.getenv("POSTGRES_HOST"),
        "port": os.getenv("POSTGRES_PORT"),
        "database": os.getenv("POSTGRES_DB"),
        "user": os.getenv("POSTGRES_USER"),
        "password": os.getenv("POSTGRES_PASSWORD"),
    }

    missing = [key for key, value in config.items() if not value]

    if missing:
        raise ValueError(
            f"Missing required database environment variables: {', '.join(missing)}"
        )

    connection_url = (
        f"postgresql+psycopg2://{config['user']}:{config['password']}"
        f"@{config['host']}:{config['port']}/{config['database']}"
    )

    return create_engine(connection_url)

def read_query(query: str) -> pd.DataFrame:
    engine = get_engine()

    with engine.connect() as connection:
        return pd.read_sql(query, connection)