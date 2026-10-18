"""Background job execution.

A small in-process worker pool runs inspection jobs. Job and stage state are persisted in the
database, so the API (and the Flutter client polling it) always sees the real state. On
startup, jobs left ``running`` by a previous process are marked failed (they cannot be resumed
safely) and ``queued`` jobs are re-submitted.

Redis/Celery were deliberately not added: one worker process with persisted state is enough for
a laptop deployment, and the job abstraction keeps the door open for a queue later.
"""
from __future__ import annotations

import threading
from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import select

from ..core.config import get_settings
from ..core.db import session_scope
from ..core.logging import get_logger
from ..core.util import utcnow
from ..models import InspectionVersion, ProcessingJob

log = get_logger("workers")

_executor: ThreadPoolExecutor | None = None
_lock = threading.Lock()


def executor() -> ThreadPoolExecutor:
    global _executor
    with _lock:
        if _executor is None:
            _executor = ThreadPoolExecutor(max_workers=max(1, get_settings().job_workers), thread_name_prefix="eagleeye-job")
        return _executor


def submit(job_id: str) -> None:
    from ..inspection.pipeline import run_job

    def _run() -> None:
        try:
            run_job(job_id)
        except Exception:  # run_job records failures itself; this is a last-resort guard
            log.exception("Job %s crashed outside stage handling", job_id)

    executor().submit(_run)


def recover_jobs() -> dict:
    failed, requeued = 0, []
    with session_scope() as db:
        for job in db.scalars(select(ProcessingJob).where(ProcessingJob.status.in_(["running", "queued"]))):
            if job.status == "running":
                job.status = "failed"
                job.error = "Interrupted: the server stopped while this job was running. Start the run again."
                job.finished_at = utcnow()
                for st in job.stages:
                    if st.status == "running":
                        st.status = "failed"
                        st.message = "Interrupted by server restart"
                    elif st.status == "pending":
                        st.status = "skipped"
                        st.message = "Not executed: job interrupted"
                ver = db.get(InspectionVersion, job.version_id)
                if ver and ver.status == "running":
                    ver.status = "failed"
                    ver.error = job.error
                failed += 1
            else:
                requeued.append(job.id)
    for jid in requeued:
        submit(jid)
    if failed or requeued:
        log.info("Job recovery", extra={"ctx": {"failed_interrupted": failed, "requeued": len(requeued)}})
    return {"failed": failed, "requeued": len(requeued)}


def shutdown() -> None:
    global _executor
    with _lock:
        if _executor is not None:
            _executor.shutdown(wait=False, cancel_futures=True)
            _executor = None
