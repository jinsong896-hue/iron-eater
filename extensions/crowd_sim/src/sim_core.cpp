#include "sim_core.h"

#include <algorithm>
#include <atomic>
#include <cmath>

namespace crowd {

namespace {
// 邻居查询半径（米）——超过这个距离不参与斥力
constexpr float NEIGHBOR_RADIUS = 1.6f;
// 斥力强度系数（越大越"挤不开"）
constexpr float REPULSION_STRENGTH = 6.0f;
// 转向速率（每秒插值比例）——越大转向越急
constexpr float TURN_RATE = 6.0f;
// 与目标的停止距离（避免贴着目标抖动）
constexpr float ARRIVE_EPS = 0.35f;
// 障碍碰撞把实例推出的最小修正量，防止数值上卡在边界
constexpr float COLLISION_SKIN = 0.001f;

inline float clampf(float v, float lo, float hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}
} // namespace

SimCore::SimCore() {}

void SimCore::setup(int capacity, float cell_size) {
	capacity_ = std::max(1, std::min(capacity, CAP));
	cell_size_ = cell_size > 0.01f ? cell_size : 2.0f;

	for (int b = 0; b < 2; ++b) {
		px_[b].assign(static_cast<size_t>(capacity_), 0.0f);
		pz_[b].assign(static_cast<size_t>(capacity_), 0.0f);
	}
	vx_.assign(static_cast<size_t>(capacity_), 0.0f);
	vz_.assign(static_cast<size_t>(capacity_), 0.0f);
	hp_.assign(static_cast<size_t>(capacity_), 0.0f);
	max_hp_.assign(static_cast<size_t>(capacity_), 0.0f);
	speed_.assign(static_cast<size_t>(capacity_), 0.0f);
	radius_.assign(static_cast<size_t>(capacity_), 0.3f);
	scale_.assign(static_cast<size_t>(capacity_), 1.0f);
	stagger_.assign(static_cast<size_t>(capacity_), 0.0f);
	atk_cd_.assign(static_cast<size_t>(capacity_), 0.0f);
	flags_.assign(static_cast<size_t>(capacity_), 0u);
	target_id_.assign(static_cast<size_t>(capacity_), -1);

	hash_of_.assign(static_cast<size_t>(capacity_), 0);
	sorted_ids_.assign(static_cast<size_t>(capacity_), 0);

	counts_.assign(MAX_CELLS, 0);
	cell_start_.assign(MAX_CELLS, 0);
	cell_end_.assign(MAX_CELLS, 0);

	free_list_.clear();
	free_list_.reserve(static_cast<size_t>(capacity_));
	// 逆序压栈：spawn 时从尾部弹，于是 id 从小到大分配（便于调试观察）
	for (int i = capacity_ - 1; i >= 0; --i) {
		free_list_.push_back(i);
	}
	active_ = 0;
	cur_buf_ = 0;
	grid_w_ = grid_h_ = 0;
	cell_count_ = 0;
	obstacles_.clear();
	events_.clear();
}

void SimCore::set_obstacles(const std::vector<AABB> &obstacles) {
	obstacles_ = obstacles;
}

int SimCore::spawn(float x, float z, float hp, float speed, float radius, float scale) {
	if (free_list_.empty()) {
		return -1;
	}
	const int id = free_list_.back();
	free_list_.pop_back();

	px_[cur_buf_][id] = x;
	pz_[cur_buf_][id] = z;
	px_[1 - cur_buf_][id] = x;
	pz_[1 - cur_buf_][id] = z;
	vx_[id] = 0.0f;
	vz_[id] = 0.0f;
	hp_[id] = hp;
	max_hp_[id] = hp;
	speed_[id] = speed;
	radius_[id] = radius;
	scale_[id] = scale;
	stagger_[id] = 0.0f;
	atk_cd_[id] = 0.0f;
	flags_[id] = SIM_ALIVE;
	target_id_[id] = -1;

	++active_;
	return id;
}

void SimCore::despawn(int id) {
	if (id < 0 || id >= capacity_) {
		return;
	}
	if ((flags_[id] & SIM_ALIVE) == 0) {
		return;
	}
	flags_[id] = 0u;
	free_list_.push_back(id);
	--active_;
}

bool SimCore::is_alive(int id) const {
	return id >= 0 && id < capacity_ && (flags_[id] & SIM_ALIVE) != 0;
}

void SimCore::set_stagger(int id, float seconds) {
	if (id < 0 || id >= capacity_) {
		return;
	}
	stagger_[id] = seconds > 0.0f ? seconds : 0.0f;
	if (stagger_[id] > 0.0f) {
		flags_[id] |= SIM_STAGGERED;
	} else {
		flags_[id] &= ~SIM_STAGGERED;
	}
}

void SimCore::set_elite_flag(int id, bool elite) {
	if (id < 0 || id >= capacity_) {
		return;
	}
	if (elite) {
		flags_[id] |= SIM_ELITE;
	} else {
		flags_[id] &= ~SIM_ELITE;
	}
}

void SimCore::set_target(int id, int target_id) {
	if (id < 0 || id >= capacity_) {
		return;
	}
	target_id_[id] = target_id;
}

// ============================================================
// 空间哈希：六步流水线
// ============================================================

int SimCore::cell_x(float x) const {
	return static_cast<int>((x - origin_x_) / cell_size_);
}

int SimCore::cell_z(float z) const {
	return static_cast<int>((z - origin_z_) / cell_size_);
}

int SimCore::cell_of(float x, float z) const {
	int cx = cell_x(x);
	int cz = cell_z(z);
	cx = cx < 0 ? 0 : (cx >= grid_w_ ? grid_w_ - 1 : cx);
	cz = cz < 0 ? 0 : (cz >= grid_h_ ? grid_h_ - 1 : cz);
	return cz * grid_w_ + cx;
}

void SimCore::build_hash() {
	if (active_ == 0) {
		cell_count_ = 0;
		return;
	}

	// 步骤 1：包围盒（并行分块求 min/max，再归约）
	// 用"每个分块各自 min/max 写进槽位，最后串行归约"避免原子浮点。
	struct Range {
		float min_x, min_z, max_x, max_z;
	};
	const int chunks = std::max(1, pool_.size());
	std::vector<Range> ranges(static_cast<size_t>(chunks));

	pool_.parallel_for(chunks, [&](int b, int e) {
		Range r{1e30f, 1e30f, -1e30f, -1e30f};
		// 按 id 扫描（活跃实例未必连续，用 flags 过滤）
		const int per = capacity_ / chunks;
		const int rem = capacity_ % chunks;
		for (int c = b; c < e; ++c) {
			const int begin = c * per + std::min(c, rem);
			const int end = begin + per + (c < rem ? 1 : 0);
			for (int i = begin; i < end; ++i) {
				if ((flags_[i] & SIM_ALIVE) == 0) {
					continue;
				}
				const float x = px_[cur_buf_][i];
				const float z = pz_[cur_buf_][i];
				if (x < r.min_x) r.min_x = x;
				if (z < r.min_z) r.min_z = z;
				if (x > r.max_x) r.max_x = x;
				if (z > r.max_z) r.max_z = z;
			}
		}
		ranges[b] = r;
	});

	Range box{1e30f, 1e30f, -1e30f, -1e30f};
	for (const Range &r : ranges) {
		if (r.min_x < box.min_x) box.min_x = r.min_x;
		if (r.min_z < box.min_z) box.min_z = r.min_z;
		if (r.max_x > box.max_x) box.max_x = r.max_x;
		if (r.max_z > box.max_z) box.max_z = r.max_z;
	}
	// 全部活跃实例在同一个点上时盒退化，撑开一点避免除零
	if (!(box.max_x > box.min_x)) {
		box.min_x -= cell_size_;
		box.max_x += cell_size_;
	}
	if (!(box.max_z > box.min_z)) {
		box.min_z -= cell_size_;
		box.max_z += cell_size_;
	}

	// 网格维度：按包围盒 + 一圈余量（邻居查询要扫 3x3，边缘需要邻居格存在）
	origin_x_ = box.min_x - cell_size_;
	origin_z_ = box.min_z - cell_size_;
	grid_w_ = static_cast<int>((box.max_x - box.min_x) / cell_size_) + 3;
	grid_h_ = static_cast<int>((box.max_z - box.min_z) / cell_size_) + 3;

	// 格子总数封顶：超出就放大 cell_size 重算，直到装得下
	while (grid_w_ * grid_h_ > MAX_CELLS) {
		cell_size_ *= 1.5f;
		grid_w_ = static_cast<int>((box.max_x - box.min_x) / cell_size_) + 3;
		grid_h_ = static_cast<int>((box.max_z - box.min_z) / cell_size_) + 3;
	}
	cell_count_ = grid_w_ * grid_h_;
	std::fill(counts_.begin(), counts_.begin() + cell_count_, 0);
	std::fill(cell_start_.begin(), cell_start_.begin() + cell_count_, 0);
	std::fill(cell_end_.begin(), cell_end_.begin() + cell_count_, 0);

	// 步骤 2：哈希分配 + 原子计数
	{
		std::atomic<int> *counts = reinterpret_cast<std::atomic<int> *>(counts_.data());
		pool_.parallel_for(capacity_, [&](int b, int e) {
			for (int i = b; i < e; ++i) {
				if ((flags_[i] & SIM_ALIVE) == 0) {
					hash_of_[i] = -1;
					continue;
				}
				const int h = cell_of(px_[cur_buf_][i], pz_[cur_buf_][i]);
				hash_of_[i] = h;
				counts[h].fetch_add(1, std::memory_order_relaxed);
			}
		});
	}

	// 步骤 3：前缀和（串行，O(cell_count)；cell_count ≤ 8192，代价可忽略）
	{
		int sum = 0;
		for (int c = 0; c < cell_count_; ++c) {
			const int n = counts_[c];
			cell_start_[c] = sum;
			sum += n;
			cell_end_[c] = sum;
			counts_[c] = sum - n;   // 还原成"下一个可写槽位"
		}
	}

	// 步骤 4：放置（原子 fetch-add 拿槽位 → 等价于按格子基数排序）
	{
		std::atomic<int> *cursor = reinterpret_cast<std::atomic<int> *>(counts_.data());
		pool_.parallel_for(capacity_, [&](int b, int e) {
			for (int i = b; i < e; ++i) {
				const int h = hash_of_[i];
				if (h < 0) {
					continue;
				}
				const int slot = cursor[h].fetch_add(1, std::memory_order_relaxed);
				if (slot < capacity_) {
					sorted_ids_[slot] = i;
				}
			}
		});
	}

	// 步骤 5/6 已由上面前缀和填入的 cell_start_/cell_end_ 覆盖，
	// 无需额外一趟（参考项目分两步是因为它把 start/end 分开存）。
}

// ============================================================
// 四阶段模拟
// ============================================================

// 阶段 2：邻居斥力 + 朝目标期望速度 + 转向插值
void SimCore::phase_steer(float dt, float player_x, float player_z) {
	const int wb = 1 - cur_buf_;
	const float r2_sum_base = NEIGHBOR_RADIUS * NEIGHBOR_RADIUS;

	pool_.parallel_for(capacity_, [&](int b, int e) {
		for (int i = b; i < e; ++i) {
			if ((flags_[i] & SIM_ALIVE) == 0) {
				continue;
			}
			// 硬直中：只减速，不主动移动（被击退的速度仍会积分）
			if (stagger_[i] > 0.0f) {
				stagger_[i] -= dt;
				if (stagger_[i] <= 0.0f) {
					stagger_[i] = 0.0f;
					flags_[i] &= ~SIM_STAGGERED;
				}
				continue;
			}

			const float x = px_[cur_buf_][i];
			const float z = pz_[cur_buf_][i];

			// —— 目标：target_id_ < 0 表示跟随玩家 ——
			float tx = player_x;
			float tz = player_z;
			const int tid = target_id_[i];
			if (tid >= 0 && (flags_[tid] & SIM_ALIVE) != 0) {
				tx = px_[cur_buf_][tid];
				tz = pz_[cur_buf_][tid];
			}

			float dx = tx - x;
			float dz = tz - z;
			const float dist = std::sqrt(dx * dx + dz * dz);
			float des_vx = 0.0f;
			float des_vz = 0.0f;
			if (dist > ARRIVE_EPS) {
				const float inv = 1.0f / dist;
				des_vx = dx * inv * speed_[i];
				des_vz = dz * inv * speed_[i];
			}

			// —— 邻居扫描（3x3 邻格）在下面与斥力合并成一趟 ——
			// 早期版本在这里单独算一遍 rep_x/rep_z 加进速度，但那样会被
			// 限速 clamp 掉。现在斥力直接改位置，故这一趟只需算格坐标。
			const int cx = cell_x(x);
			const int cz = cell_z(z);

			// —— 转向：速度朝期望方向插值（**只含 seek，斥力不在这里**） ——
			const float lerp_t = clampf(TURN_RATE * dt, 0.0f, 1.0f);
			float nvx = vx_[i] + (des_vx - vx_[i]) * lerp_t;
			float nvz = vz_[i] + (des_vz - vz_[i]) * lerp_t;
			// 限速：不超过该实例的移动速度
			const float sp = speed_[i];
			const float v2 = nvx * nvx + nvz * nvz;
			if (v2 > sp * sp && v2 > 1e-8f) {
				const float inv = sp / std::sqrt(v2);
				nvx *= inv;
				nvz *= inv;
			}
			vx_[i] = nvx;
			vz_[i] = nvz;

			// —— 斥力直接作用于**位置**，不经过速度 ——
			// **这是必须的**：早期版本把斥力加进速度再限速，结果斥力被
			// clamp 掉，100 只挤在一起时最小间距只有 0.056（几乎完全重叠）。
			// 位置修正不受速度上限约束，才能真正把重叠解开。
			//
			// **硬分离累加重叠量**（不是只取最大者）：20 只挤在同一个目标点
			// 时每帧只解开一个邻居的收敛太慢（实测 240 帧后最小间距仍 0.012）。
			// 累加本身不会炸——下面有 max_push 限幅兜底（早期穿墙是"累加且
			// 无限幅"共同造成的，限幅加上后累加是安全的）。
			// 软斥力（非重叠时的保持间距）同样累加——那是多方向的合力，合理。
			float push_x = 0.0f;
			float push_z = 0.0f;
			for (int oz2 = -1; oz2 <= 1; ++oz2) {
				const int nz = cz + oz2;
				if (nz < 0 || nz >= grid_h_) {
					continue;
				}
				for (int ox2 = -1; ox2 <= 1; ++ox2) {
					const int nx = cx + ox2;
					if (nx < 0 || nx >= grid_w_) {
						continue;
					}
					const int cell = nz * grid_w_ + nx;
					const int s = cell_start_[cell];
					const int t = cell_end_[cell];
					for (int k = s; k < t; ++k) {
						const int j = sorted_ids_[k];
						if (j == i || (flags_[j] & SIM_ALIVE) == 0) {
							continue;
						}
						const float ddx = x - px_[cur_buf_][j];
						const float ddz = z - pz_[cur_buf_][j];
						const float d2 = ddx * ddx + ddz * ddz;
						const float r_sum = radius_[i] + radius_[j];
						if (d2 < 1e-8f) {
							// 完全重合：用 id 派生一个确定方向，避免除零且可复现
							const float ang = float((i * 2654435761u) % 628) * 0.01f;
							push_x += std::cos(ang) * r_sum * 0.25f;
							push_z += std::sin(ang) * r_sum * 0.25f;
							continue;
						}
						const float d = std::sqrt(d2);
						const float nxu = ddx / d;
						const float nzu = ddz / d;
						if (d < r_sum) {
							// 硬分离：推开重叠量的一半（双方各推一半 = 相对满量）
							const float overlap = (r_sum - d) * 0.5f;
							push_x += nxu * overlap;
							push_z += nzu * overlap;
						} else if (d < NEIGHBOR_RADIUS) {
							// 软斥力：越近越强，除以 lim 而非 d 以**有界**
							//（除以 d 会在 d→0 时爆掉，把单位弹飞）
							const float f = REPULSION_STRENGTH
									* (1.0f - d / NEIGHBOR_RADIUS) / NEIGHBOR_RADIUS;
							push_x += nxu * f * dt;
							push_z += nzu * f * dt;
						}
					}
				}
			}
			// 总位移限幅：单帧位置修正不超过该实例的移动速度，
			// 否则密集群体里的合力仍可能把单位瞬移穿墙
			const float p2 = push_x * push_x + push_z * push_z;
			const float max_push = speed_[i] * dt * 2.0f;
			if (p2 > max_push * max_push && p2 > 1e-8f) {
				const float inv = max_push / std::sqrt(p2);
				push_x *= inv;
				push_z *= inv;
			}

			// 写回：位置 = 当前位置 + 斥力位移（速度在下一阶段积分）
			px_[wb][i] = x + push_x;
			pz_[wb][i] = z + push_z;
		}
	});
}

// 阶段 3：障碍 AABB 碰撞（房间墙 <200 个，暴力比建树划算）
void SimCore::phase_collide_obstacles() {
	if (obstacles_.empty()) {
		return;
	}
	const int wb = 1 - cur_buf_;
	pool_.parallel_for(capacity_, [&](int b, int e) {
		for (int i = b; i < e; ++i) {
			if ((flags_[i] & SIM_ALIVE) == 0) {
				continue;
			}
			float x = px_[wb][i];
			float z = pz_[wb][i];
			const float r = radius_[i];
			for (const AABB &a : obstacles_) {
				// 圆心到盒的最近点
				const float cxp = clampf(x, a.min_x, a.max_x);
				const float czp = clampf(z, a.min_z, a.max_z);
				const float dx = x - cxp;
				const float dz = z - czp;
				const float d2 = dx * dx + dz * dz;
				if (d2 >= r * r) {
					continue;
				}
				if (d2 > 1e-8f) {
					// 圆心在盒外：沿最近点方向推出
					const float d = std::sqrt(d2);
					const float push = r - d + COLLISION_SKIN;
					const float nx = dx / d;
					const float nz = dz / d;
					x += nx * push;
					z += nz * push;
					// 清掉指向墙内的速度分量（沿墙滑动，不是硬停）
					const float vn = vx_[i] * nx + vz_[i] * nz;
					if (vn < 0.0f) {
						vx_[i] -= vn * nx;
						vz_[i] -= vn * nz;
					}
				} else {
					// 圆心陷在盒内：弹回**进入前所在的那一侧**。
					//
					// **薄墙的坑**：纯"最小穿透轴"在薄墙上会把单位推到远侧，
					// 等于穿墙（实测 100 只里有 15 只穿过了 0.5 米宽的墙）。
					// 判据用 cur_buf_ 里的**上一帧位置**（本阶段读它、写 wb）：
					// 上一帧在墙左侧 → 弹回左侧，与当前速度无关，因而对
					// "被斥力推进墙里"这种零速度情况同样正确。
					const float prev_x = px_[cur_buf_][i];
					const float prev_z = pz_[cur_buf_][i];
					const float pdl = prev_x - a.min_x;
					const float pdr = a.max_x - prev_x;
					const float pdt = prev_z - a.min_z;
					const float pdb = a.max_z - prev_z;
					// 上一帧在盒外：取"上一帧离哪条边最近"的那条边弹回
					if (pdl <= 0.0f || pdr <= 0.0f || pdt <= 0.0f || pdb <= 0.0f) {
						const float m = std::min(std::min(pdl, pdr), std::min(pdt, pdb));
						if (m == pdl) {
							x = a.min_x - r - COLLISION_SKIN;
							if (vx_[i] > 0.0f) vx_[i] = 0.0f;
						} else if (m == pdr) {
							x = a.max_x + r + COLLISION_SKIN;
							if (vx_[i] < 0.0f) vx_[i] = 0.0f;
						} else if (m == pdt) {
							z = a.min_z - r - COLLISION_SKIN;
							if (vz_[i] > 0.0f) vz_[i] = 0.0f;
						} else {
							z = a.max_z + r + COLLISION_SKIN;
							if (vz_[i] < 0.0f) vz_[i] = 0.0f;
						}
					} else {
						// 上一帧也在盒内（初始就刷在墙里）：退回最小穿透轴
						const float dl = x - a.min_x;
						const float dr = a.max_x - x;
						const float dt_ = z - a.min_z;
						const float db = a.max_z - z;
						const float m = std::min(std::min(dl, dr), std::min(dt_, db));
						if (m == dl) {
							x = a.min_x - r - COLLISION_SKIN;
						} else if (m == dr) {
							x = a.max_x + r + COLLISION_SKIN;
						} else if (m == dt_) {
							z = a.min_z - r - COLLISION_SKIN;
						} else {
							z = a.max_z + r + COLLISION_SKIN;
						}
					}
				}
			}
			px_[wb][i] = x;
			pz_[wb][i] = z;
		}
	});
}

// 阶段 4：位置积分
void SimCore::phase_integrate(float dt) {
	const int wb = 1 - cur_buf_;
	pool_.parallel_for(capacity_, [&](int b, int e) {
		for (int i = b; i < e; ++i) {
			if ((flags_[i] & SIM_ALIVE) == 0) {
				continue;
			}
			px_[wb][i] += vx_[i] * dt;
			pz_[wb][i] += vz_[i] * dt;
		}
	});
}

void SimCore::step(float dt, float player_x, float player_z) {
	if (active_ == 0) {
		return;
	}
	build_hash();
	phase_steer(dt, player_x, player_z);
	phase_attack(dt, player_x, player_z);
	phase_collide_obstacles();
	phase_integrate(dt);
}


// 攻击阶段：进入 attack_range 的单位按 attack_interval 对玩家造成伤害。
//
// **伤害不由本核结算**——核不知道玩家的护甲/减伤/无敌帧，也没有
// EventBus。这里只负责"谁在何时打了多少"，发事件给 GDScript 侧走
// 正常的 take_damage 链路（与节点式敌人同一套结算）。
//
// 放在 phase_steer 之后：用本帧的意图速度判断是否已贴脸，
// 避免"刚进范围就被打"的滞后感。
void SimCore::phase_attack(float dt, float player_x, float player_z) {
	const float r2 = attack_range_ * attack_range_;
	for (int i = 0; i < capacity_; ++i) {
		if (!(flags_[i] & SIM_ALIVE)) {
			continue;
		}
		// 冷却推进（无论是否在范围内，保证离开再回来不会立刻打）
		if (atk_cd_[i] > 0.0f) {
			atk_cd_[i] -= dt;
		}
		const float dx = px_[cur_buf_][i] - player_x;
		const float dz = pz_[cur_buf_][i] - player_z;
		if (dx * dx + dz * dz > r2) {
			continue;
		}
		if (atk_cd_[i] > 0.0f) {
			continue;
		}
		atk_cd_[i] = attack_interval_;
		SimEvent e;
		e.type = SIM_EVENT_ATTACK;
		e.id = i;
		e.x = px_[cur_buf_][i];
		e.z = pz_[cur_buf_][i];
		e.is_elite = (flags_[i] & SIM_ELITE) ? 1 : 0;
		e.damage = attack_damage_;
		events_.push_back(e);
	}
}

// ============================================================
// 查询与伤害
// ============================================================

void SimCore::query_circle(float cx, float cz, float radius,
		std::vector<int> &out) const {
	out.clear();
	if (active_ == 0 || grid_w_ <= 0) {
		return;
	}
	const float r2 = radius * radius;
	// 只扫圆形覆盖的格子范围（比全场遍历快得多）
	const int min_cx = std::max(0, cell_x(cx - radius));
	const int max_cx = std::min(grid_w_ - 1, cell_x(cx + radius));
	const int min_cz = std::max(0, cell_z(cz - radius));
	const int max_cz = std::min(grid_h_ - 1, cell_z(cz + radius));
	for (int gz = min_cz; gz <= max_cz; ++gz) {
		for (int gx = min_cx; gx <= max_cx; ++gx) {
			const int cell = gz * grid_w_ + gx;
			for (int k = cell_start_[cell]; k < cell_end_[cell]; ++k) {
				const int j = sorted_ids_[k];
				if ((flags_[j] & SIM_ALIVE) == 0) {
					continue;
				}
				const float dx = px_[cur_buf_][j] - cx;
				const float dz = pz_[cur_buf_][j] - cz;
				if (dx * dx + dz * dz <= r2) {
					out.push_back(j);
				}
			}
		}
	}
}

void SimCore::query_cone(float ox, float oz, float dir_x, float dir_z,
		float cos_half_angle, float range, std::vector<int> &out) const {
	out.clear();
	if (active_ == 0 || grid_w_ <= 0) {
		return;
	}
	const float len = std::sqrt(dir_x * dir_x + dir_z * dir_z);
	if (len < 1e-6f) {
		return;
	}
	const float ux = dir_x / len;
	const float uz = dir_z / len;
	const float r2 = range * range;

	const int min_cx = std::max(0, cell_x(ox - range));
	const int max_cx = std::min(grid_w_ - 1, cell_x(ox + range));
	const int min_cz = std::max(0, cell_z(oz - range));
	const int max_cz = std::min(grid_h_ - 1, cell_z(oz + range));
	for (int gz = min_cz; gz <= max_cz; ++gz) {
		for (int gx = min_cx; gx <= max_cx; ++gx) {
			const int cell = gz * grid_w_ + gx;
			for (int k = cell_start_[cell]; k < cell_end_[cell]; ++k) {
				const int j = sorted_ids_[k];
				if ((flags_[j] & SIM_ALIVE) == 0) {
					continue;
				}
				const float dx = px_[cur_buf_][j] - ox;
				const float dz = pz_[cur_buf_][j] - oz;
				const float d2 = dx * dx + dz * dz;
				if (d2 > r2 || d2 < 1e-8f) {
					continue;
				}
				const float d = std::sqrt(d2);
				// 与朝向的夹角余弦（>= cos_half_angle 即在锥内）
				if ((dx * ux + dz * uz) / d >= cos_half_angle) {
					out.push_back(j);
				}
			}
		}
	}
}

int SimCore::apply_damage(const std::vector<int> &ids, float amount) {
	int kills = 0;
	for (int id : ids) {
		if (!is_alive(id)) {
			continue;
		}
		hp_[id] -= amount;
		if (hp_[id] <= 0.0f) {
			hp_[id] = 0.0f;
			// 死亡事件：位置用读缓冲（本帧渲染的那份）
			SimEvent ev;
			ev.type = SIM_EVENT_DEATH;
			ev.id = id;
			ev.x = px_[cur_buf_][id];
			ev.z = pz_[cur_buf_][id];
			ev.is_elite = (flags_[id] & SIM_ELITE) ? 1 : 0;
			ev.damage = 0.0f;
			events_.push_back(ev);
			despawn(id);
			++kills;
		}
	}
	return kills;
}

void SimCore::drain_events(std::vector<SimEvent> &out) {
	out.swap(events_);
	events_.clear();
}

} // namespace crowd
