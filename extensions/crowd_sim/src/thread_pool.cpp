#include "thread_pool.h"

#include <algorithm>

namespace crowd {

ThreadPool::ThreadPool(int thread_count) {
	if (thread_count <= 0) {
		unsigned hw = std::thread::hardware_concurrency();
		// 留一个核给主线程（渲染/脚本），避免模拟把帧率吃满
		thread_count = hw > 1 ? static_cast<int>(hw) - 1 : 1;
	}
	workers_.reserve(static_cast<size_t>(thread_count));
	for (int i = 0; i < thread_count; ++i) {
		workers_.emplace_back([this, i]() { worker_loop(i); });
	}
}

ThreadPool::~ThreadPool() {
	{
		std::lock_guard<std::mutex> lock(mutex_);
		shutdown_ = true;
		++generation_;
	}
	cv_start_.notify_all();
	for (auto &t : workers_) {
		if (t.joinable()) {
			t.join();
		}
	}
}

void ThreadPool::worker_loop(int worker_index) {
	int seen = 0;
	for (;;) {
		const std::function<void(int, int)> *task = nullptr;
		int begin = 0;
		int end = 0;
		// 本 worker 这一轮是否真的领到了活。
		// **只有领到活的才递减 pending_**——块数可能少于线程数
		//（任务小时 chunks = count），若空转的 worker 也递减，
		// pending_ 会提前归零，主线程在别的 worker 还在跑时就返回。
		bool did_work = false;
		{
			std::unique_lock<std::mutex> lock(mutex_);
			cv_start_.wait(lock, [this, &seen]() { return generation_ != seen; });
			seen = generation_;
			if (shutdown_) {
				return;
			}
			task = task_;
			if (worker_index < task_chunks_) {
				const int chunk = task_count_ / task_chunks_;
				const int rem = task_count_ % task_chunks_;
				begin = worker_index * chunk + std::min(worker_index, rem);
				end = begin + chunk + (worker_index < rem ? 1 : 0);
				did_work = true;
			}
		}
		if (task != nullptr && begin < end) {
			(*task)(begin, end);
		}
		if (did_work) {
			std::lock_guard<std::mutex> lock(mutex_);
			if (--pending_ == 0) {
				cv_done_.notify_one();
			}
		}
	}
}

void ThreadPool::parallel_for(int count, const std::function<void(int, int)> &fn) {
	if (count <= 0) {
		return;
	}
	const int nthreads = size();
	// 任务太小就别付同步开销：单线程直接跑
	if (nthreads <= 1 || count < 256) {
		fn(0, count);
		return;
	}
	const int chunks = std::min(nthreads, count);
	{
		std::lock_guard<std::mutex> lock(mutex_);
		task_ = &fn;
		task_count_ = count;
		task_chunks_ = chunks;
		// pending_ 只统计**真正领到活的块**（= chunks），不是线程数
		pending_ = chunks;
		++generation_;
	}
	cv_start_.notify_all();
	{
		std::unique_lock<std::mutex> lock(mutex_);
		cv_done_.wait(lock, [this]() { return pending_ == 0; });
		task_ = nullptr;
	}
}

} // namespace crowd
