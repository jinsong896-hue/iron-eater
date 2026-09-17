#ifndef CROWD_THREAD_POOL_H
#define CROWD_THREAD_POOL_H

// 轻量并行 for 线程池。
//
// 为什么自建而不用 Godot 的 WorkerThreadPool：模拟核（sim_core）刻意
// **不依赖任何 Godot 类型**，这样才能独立编译、独立基准测试、也便于
// 将来换后端。唯一的跨线程约束是"构造 PackedArray 必须回主线程"，
// 那条约束由 CrowdSim 绑定层负责，与本池无关。

#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

namespace crowd {

class ThreadPool {
public:
	explicit ThreadPool(int thread_count = 0);
	~ThreadPool();

	ThreadPool(const ThreadPool &) = delete;
	ThreadPool &operator=(const ThreadPool &) = delete;

	// 把 [0, count) 切成 n 块并行跑 fn(begin, end)。
	// **阻塞直到全部完成**——调用方在"提交后立刻 wait"的模式下用它最直观
	//（异步由上层双缓冲负责，池本身不需要也异步）。
	void parallel_for(int count, const std::function<void(int, int)> &fn);

	int size() const { return static_cast<int>(workers_.size()); }

private:
	void worker_loop(int worker_index);

	std::vector<std::thread> workers_;
	std::mutex mutex_;
	std::condition_variable cv_start_;
	std::condition_variable cv_done_;

	// 每一轮任务的代际号：worker 等 generation_ 变化即开工
	int generation_ = 0;
	int pending_ = 0;
	bool shutdown_ = false;

	const std::function<void(int, int)> *task_ = nullptr;
	int task_count_ = 0;
	int task_chunks_ = 0;
};

} // namespace crowd

#endif // CROWD_THREAD_POOL_H
