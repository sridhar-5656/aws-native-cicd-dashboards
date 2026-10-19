from __future__ import annotations

import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


def get_process_memory_mb() -> Optional[float]:
    try:
        import sys
        if sys.platform == "win32":
            import ctypes
            import os
            from ctypes import wintypes

            class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
                _fields_ = [
                    ("cb", wintypes.DWORD),
                    ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]

            pmc = PROCESS_MEMORY_COUNTERS()
            pmc.cb = ctypes.sizeof(PROCESS_MEMORY_COUNTERS)
            # 0x0410 = PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
            h = ctypes.windll.kernel32.OpenProcess(0x0410, False, os.getpid())
            if h:
                try:
                    if ctypes.windll.psapi.GetProcessMemoryInfo(h, ctypes.byref(pmc), pmc.cb):
                        return round(pmc.WorkingSetSize / (1024 * 1024), 2)
                finally:
                    ctypes.windll.kernel32.CloseHandle(h)
        else:
            import resource
            rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            divisor = 1024 if sys.platform.startswith("linux") else (1024 * 1024)
            return round(rss / divisor, 2)
    except Exception:
        pass
    return None


@dataclass
class RuntimeState:
    started_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    _started_monotonic: float = field(default_factory=time.monotonic)
    startup_complete: bool = False
    shutting_down: bool = False
    request_count: int = 0

    @property
    def uptime_seconds(self) -> float:
        return round(time.monotonic() - self._started_monotonic, 3)

    @property
    def memory_mb(self) -> Optional[float]:
        return get_process_memory_mb()


def frontend_assets_present(static_dir: Path) -> bool:
    return (static_dir / "index.html").is_file()

