def test_health_and_openapi(client):
    assert client.get("/api/v1/health").json()["status"] == "ok"
    spec = client.get("/api/v1/openapi.json").json()
    assert "/api/v1/inspections" in spec["paths"] and "/api/v1/findings/{finding_id}/reviews" in spec["paths"]


def test_create_upload_validate(client, demo_dir):
    r = client.post("/api/v1/inspections", json={"title": "API test", "cabinet_id": "CAB-T"})
    assert r.status_code == 201
    insp = r.json()
    assert insp["code"].startswith("EYE-") and insp["versions"][0]["status"] == "draft"
    vid = insp["versions"][0]["id"]
    # wrong type / spoofed extension
    bad = client.post(f"/api/v1/versions/{vid}/assets", data={"kind": "photo"}, files={"file": ("x.jpg", b"%PDF-1.4 fake", "image/jpeg")})
    assert bad.status_code == 400 and bad.json()["error"]["code"] == "invalid_file_type"
    empty = client.post(f"/api/v1/versions/{vid}/assets", data={"kind": "drawing"}, files={"file": ("x.pdf", b"", "application/pdf")})
    assert empty.status_code == 400
    up = client.post(f"/api/v1/versions/{vid}/assets", data={"kind": "drawing"},
                     files={"file": ("ga.pdf", (demo_dir / "CAB-07_GA_drawing_SYNTHETIC.pdf").read_bytes(), "application/pdf")})
    assert up.status_code == 201 and up.json()["analysis"]["page_count"] == 1
    lst = client.post(f"/api/v1/versions/{vid}/assets", data={"kind": "expected_list"},
                      files={"file": ("list.xlsx", (demo_dir / "CAB-07_expected_list_SYNTHETIC.xlsx").read_bytes(), "application/octet-stream")})
    assert lst.status_code == 201
    rd = client.get(f"/api/v1/versions/{vid}/readiness").json()
    assert rd["ready"] is False and any(i["key"] == "photo" and i["status"] == "error" for i in rd["items"])
    run = client.post(f"/api/v1/versions/{vid}/run")
    assert run.status_code == 400 and run.json()["error"]["code"] == "not_ready"
    cfg = client.patch(f"/api/v1/versions/{vid}/config", json={"checks": ["nonsense"]})
    assert cfg.status_code == 400
    prev = client.post(f"/api/v1/assets/{lst.json()['id']}/spreadsheet/preview", json={"sheets": None}).json()
    assert prev["counts"]["components"] == 13 and prev["counts"]["identifiers"] == 10


def test_not_found_and_validation_errors(client):
    r = client.get("/api/v1/inspections/does-not-exist")
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"
    r2 = client.post("/api/v1/inspections", json={"title": "", "cabinet_id": "x"})
    assert r2.status_code == 422 and r2.json()["error"]["code"] == "validation_error"


def test_analytics_and_queue_empty_ok(client):
    a = client.get("/api/v1/analytics/overview").json()
    assert a["accuracy"]["measured"] is False
    assert "kpis" in a
    assert client.get("/api/v1/review-queue").status_code == 200
