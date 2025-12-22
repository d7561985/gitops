"""Debug handlers for Sentry demo purposes"""
import os
import time
import asyncio
import threading
import numpy as np
import psutil
import tornado
import sentry_sdk
from tornado import web


class DebugCrashHandler(web.RequestHandler):
    """Trigger various types of crashes for Sentry demo"""

    async def get(self):
        """Unhandled exception demo"""
        sentry_sdk.add_breadcrumb(
            message="User accessed debug crash endpoint",
            category="debug",
            level="info",
            data={
                "endpoint": self.request.path,
                "method": self.request.method,
                "user_ip": self.request.remote_ip
            }
        )

        sentry_sdk.set_user({
            "id": "debug-user",
            "ip_address": self.request.remote_ip
        })

        process = psutil.Process()
        sentry_sdk.set_context("runtime", {
            "memory_mb": process.memory_info().rss / 1024 / 1024,
            "cpu_percent": process.cpu_percent(interval=0.1),
            "threads": process.num_threads(),
            "python_version": os.sys.version,
            "tornado_version": tornado.version
        })

        raise RuntimeError("[DEMO] Game Engine crash triggered!")


class DebugErrorHandler(web.RequestHandler):
    """Trigger different error types"""

    async def get(self, error_type):
        """Trigger specific error types"""
        sentry_sdk.add_breadcrumb(
            message=f"Triggering {error_type} error",
            category="debug",
            level="warning",
            data={"error_type": error_type}
        )

        sentry_sdk.set_tag("error.type", error_type)
        sentry_sdk.set_tag("debug.demo", "true")

        if error_type == "value":
            int("not_a_number")
        elif error_type == "type":
            data = {"key": "value"}
            len(data())
        elif error_type == "index":
            items = [1, 2, 3]
            return items[10]
        elif error_type == "key":
            data = {"name": "test"}
            return data["missing"]
        elif error_type == "zero":
            return 100 / 0
        elif error_type == "custom":
            class GameEngineError(Exception):
                pass
            raise GameEngineError("Custom game engine error for demo")
        else:
            self.set_status(400)
            self.write({"error": f"Unknown error type: {error_type}"})


class DebugMemoryLeakHandler(web.RequestHandler):
    """Simulate memory leak"""
    _memory_leak = []

    async def get(self):
        """Create memory leak by accumulating data"""
        sentry_sdk.add_breadcrumb(
            message="Starting memory leak simulation",
            category="debug.memory",
            level="warning",
            data={"initial_items": len(self._memory_leak)}
        )

        process = psutil.Process()
        initial_memory = process.memory_info().rss / 1024 / 1024

        leak_size = 10 * 1024 * 1024
        data = 'X' * leak_size
        self._memory_leak.append(data)

        for _ in range(1000000):
            hash(data)

        final_memory = process.memory_info().rss / 1024 / 1024
        memory_increase = final_memory - initial_memory

        sentry_sdk.set_context("memory_leak", {
            "initial_memory_mb": initial_memory,
            "final_memory_mb": final_memory,
            "increase_mb": memory_increase,
            "total_leaked_items": len(self._memory_leak),
            "total_leaked_mb": len(self._memory_leak) * 10
        })

        sentry_sdk.capture_message(
            f"Memory leak demo: {memory_increase:.2f}MB increase",
            level="warning"
        )

        self.write({
            "status": "Memory leak created",
            "memory_increase_mb": memory_increase,
            "total_leaked_mb": len(self._memory_leak) * 10,
            "current_memory_mb": final_memory
        })


class DebugInfiniteLoopHandler(web.RequestHandler):
    """Simulate infinite loop / CPU spike"""

    async def get(self):
        """Create CPU spike with infinite calculation"""
        sentry_sdk.add_breadcrumb(
            message="Starting infinite loop simulation",
            category="debug.cpu",
            level="error",
            data={"warning": "This will spike CPU for 5 seconds"}
        )

        process = psutil.Process()
        sentry_sdk.set_context("cpu_spike", {
            "initial_cpu": process.cpu_percent(interval=0.1),
            "threads": process.num_threads()
        })

        start_time = time.time()
        iterations = 0

        while time.time() - start_time < 5:
            for i in range(10000):
                _ = sum(j**2 for j in range(100))
                _ = [np.sin(i) * np.cos(i) for _ in range(10)]
            iterations += 10000

            if iterations % 100000 == 0:
                await asyncio.sleep(0.001)

        final_cpu = process.cpu_percent(interval=0.1)
        sentry_sdk.capture_message(
            f"CPU spike demo completed: {iterations:,} iterations",
            level="warning"
        )

        self.write({
            "status": "CPU spike completed",
            "duration_seconds": 5,
            "iterations": iterations,
            "final_cpu_percent": final_cpu
        })


class DebugAsyncErrorHandler(web.RequestHandler):
    """Demonstrate async/await error handling"""

    async def get(self):
        """Trigger async errors"""
        sentry_sdk.add_breadcrumb(
            message="Starting async error demo",
            category="debug.async",
            level="info"
        )

        try:
            tasks = [
                self._async_task_success(),
                self._async_task_failure(),
                self._async_task_timeout()
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)

            for result in results:
                if isinstance(result, Exception):
                    sentry_sdk.capture_exception(result)

            self.write({"status": "Async demo completed"})

        except Exception as e:
            sentry_sdk.capture_exception(e)
            raise

    async def _async_task_success(self):
        await asyncio.sleep(0.1)
        return "Success"

    async def _async_task_failure(self):
        await asyncio.sleep(0.2)
        raise RuntimeError("Async task failed in coroutine")

    async def _async_task_timeout(self):
        try:
            await asyncio.wait_for(asyncio.sleep(10), timeout=0.5)
        except asyncio.TimeoutError as e:
            raise RuntimeError("Async operation timed out") from e


class DebugThreadingErrorHandler(web.RequestHandler):
    """Demonstrate threading errors"""

    def get(self):
        """Trigger threading errors"""
        sentry_sdk.add_breadcrumb(
            message="Starting threading error demo",
            category="debug.threading",
            level="warning"
        )

        threads = []

        def thread_with_error(thread_id):
            try:
                sentry_sdk.set_tag("thread.id", str(thread_id))
                sentry_sdk.add_breadcrumb(
                    message=f"Thread {thread_id} started",
                    category="thread"
                )
                time.sleep(0.1 * thread_id)

                if thread_id == 2:
                    raise ValueError(f"Thread {thread_id} encountered an error")

            except Exception as e:
                sentry_sdk.capture_exception(e)

        for i in range(3):
            thread = threading.Thread(target=thread_with_error, args=(i,))
            thread.start()
            threads.append(thread)

        for thread in threads:
            thread.join()

        self.write({
            "status": "Threading demo completed",
            "threads_created": len(threads)
        })
