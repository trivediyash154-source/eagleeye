"""Test configuration: an isolated data directory and SQLite database per test session."""
import os
import sys
import tempfile
from pathlib import Path

_TMP = tempfile.mkdtemp(prefix="eagleeye-test-")
os.environ.setdefault("EAGLEEYE_DATA_DIR", _TMP)
os.environ.setdefault("EAGLEEYE_ENVIRONMENT", "test")
os.environ.setdefault("EAGLEEYE_FRONTEND_DIST", "")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DEMO = REPO / "data" / "demo"


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: runs the real detector/OCR pipeline (needs model weights)")


@pytest.fixture(scope="session")
def demo_dir() -> Path:
    if not (DEMO / "fixtures.json").is_file():
        pytest.skip("demo fixtures not generated (run scripts/generate_demo_fixtures.py)")
    return DEMO


@pytest.fixture(scope="session")
def client():
    from fastapi.testclient import TestClient

    from app.main import app

    with TestClient(app) as c:
        yield c
