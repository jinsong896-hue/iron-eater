#include "projectile_core.h"

#include <algorithm>
#include <cmath>

namespace proj {

ProjectileCore::ProjectileCore() {}

void ProjectileCore::setup(int capacity) {
	capacity_ = std::max(capacity, 1);
	const size_t n = static_cast<size_t>(capacity_);
	for (int b = 0; b < 2; ++b) {
		px_[b].assign(n, 0.0f);
		py_[b].assign(n, 0.0f);
		pz_[b].assign(n, 0.0f);
	}
	dx_.assign(n, 0.0f);
	dz_.assign(n, 0.0f);
	speed_.assign(n, 0.0f);
	damage_.assign(n, 0.0f);
	lifetime_.assign(n, 0.0f);
	elapsed_.assign(n, 0.0f);
	elem_.assign(n, -1);
	pierce_left_.assign(n, 0);
	bounces_left_.assign(n, 0);
	hit_count_.assign(n, 0);
	faction_.assign(n, FACTION_ENEMY);
	flags_.assign(n, 0u);

	arc_sx_.assign(n, 0.0f);
	arc_sz_.assign(n, 0.0f);
	arc_lx_.assign(n, 0.0f);
	arc_lz_.assign(n, 0.0f);
	arc_h_.assign(n, 0.0f);

	fuse_time_.assign(n, 0.0f);
	fuse_timer_.assign(n, 0.0f);
	explode_radius_.assign(n, 0.0f);
	explode_damage_.assign(n, 0.0f);

	split_count_.assign(n, 0);
	split_pct_.assign(n, 0.0f);
	split_spread_.assign(n, 0.0f);
	has_zone_.assign(n, 0);

	hit_memory_.assign(n * MAX_HIT_MEMORY, -1);
	spawn_serial_.assign(n, -1);
	spawn_serial_next_ = 0;
	frame_spawn_mark_ = 0;

	free_list_.clear();
	free_list_.reserve(n);
	// 逆序压栈 → 弹出即 id 升序（与 CrowdSim 同口径，便于对照调试）
	for (int i = capacity_ - 1; i >= 0; --i) {
		free_list_.push_back(i);
	}
	active_ = 0;
	cur_buf_ = 0;
	targets_.clear();
	events_.clear();
}

void ProjectileCore::clear() {
	for (int i = 0; i < capacity_; ++i) {
		flags_[i] = 0u;
	}
	free_list_.clear();
	for (int i = capacity_ - 1; i >= 0; --i) {
		free_list_.push_back(i);
	}
	active_ = 0;
	targets_.clear();
	events_.clear();
}

int ProjectileCore::spawn(const SpawnDesc &d) {
	if (free_list_.empty()) {
		return -1;
	}
	const int id = free_list_.back();
	free_list_.pop_back();

	// 方向归一化（只取 x/z；弧线的 y 由参数化轨迹算，不用方向 y）
	float len = std::sqrt(d.dx * d.dx + d.dz * d.dz);
	float ux = 0.0f, uz = 1.0f;
	if (len > 1e-6f) {
		ux = d.dx / len;
		uz = d.dz / len;
	}

	for (int b = 0; b < 2; ++b) {
		px_[b][id] = d.x;
		py_[b][id] = d.y;
		pz_[b][id] = d.z;
	}
	dx_[id] = ux;
	dz_[id] = uz;
	speed_[id] = d.speed;
	damage_[id] = d.damage;
	lifetime_[id] = d.lifetime > 0.0f ? d.lifetime : 2.0f;
	elapsed_[id] = 0.0f;
	elem_[id] = d.elem;
	pierce_left_[id] = d.pierce;
	bounces_left_[id] = d.bounces;
	hit_count_[id] = 0;
	faction_[id] = d.faction;
	flags_[id] = P_ALIVE;
	if (d.arc) {
		flags_[id] |= P_ARC;
	}

	arc_sx_[id] = d.x;
	arc_sz_[id] = d.z;
	// 落点 = 起点 + 方向 × 速度 × max(lifetime, 1)（与既有实现同口径）
	const float travel = d.speed * std::max(d.lifetime, 1.0f);
	arc_lx_[id] = d.x + ux * travel;
	arc_lz_[id] = d.z + uz * travel;
	arc_h_[id] = d.arc_height;

	fuse_time_[id] = d.fuse;
	fuse_timer_[id] = 0.0f;
	explode_radius_[id] = d.explode_radius;
	explode_damage_[id] = d.explode_damage > 0.0f ? d.explode_damage : d.damage;

	split_count_[id] = d.split_count;
	split_pct_[id] = d.split_pct;
	split_spread_[id] = d.split_spread;
	has_zone_[id] = d.has_zone;

	// 清空去重记忆
	const int base = id * MAX_HIT_MEMORY;
	for (int k = 0; k < MAX_HIT_MEMORY; ++k) {
		hit_memory_[base + k] = -1;
	}

	spawn_serial_[id] = spawn_serial_next_++;
	++active_;
	return id;
}

void ProjectileCore::despawn(int id) {
	if (id < 0 || id >= capacity_ || !(flags_[id] & P_ALIVE)) {
		return;
	}
	flags_[id] = 0u;
	free_list_.push_back(id);
	--active_;
}

bool ProjectileCore::is_alive(int id) const {
	return id >= 0 && id < capacity_ && (flags_[id] & P_ALIVE);
}

float ProjectileCore::pos_x(int id) const { return is_alive(id) ? px_[cur_buf_][id] : 0.0f; }
float ProjectileCore::pos_y(int id) const { return is_alive(id) ? py_[cur_buf_][id] : 0.0f; }
float ProjectileCore::pos_z(int id) const { return is_alive(id) ? pz_[cur_buf_][id] : 0.0f; }
float ProjectileCore::damage_of(int id) const { return is_alive(id) ? damage_[id] : 0.0f; }
int ProjectileCore::elem_of(int id) const { return is_alive(id) ? elem_[id] : -1; }
int ProjectileCore::faction_of(int id) const { return is_alive(id) ? faction_[id] : -1; }
int ProjectileCore::pierce_left_of(int id) const { return is_alive(id) ? pierce_left_[id] : 0; }
int ProjectileCore::bounces_left_of(int id) const { return is_alive(id) ? bounces_left_[id] : 0; }
bool ProjectileCore::fuse_armed(int id) const {
	return is_alive(id) && (flags_[id] & P_FUSE_ARMED);
}

void ProjectileCore::set_targets(const std::vector<Target> &targets) {
	targets_ = targets;
}

void ProjectileCore::step(float dt) {
	if (active_ == 0) {
		return;
	}
	// 记下本帧的生成序号门槛：之后新生成的子弹（分裂小弹）跳过本轮命中判定
	frame_spawn_mark_ = spawn_serial_next_;
	phase_advance(dt);
	phase_hit_test();
	phase_lifetime();
	// 双缓冲交换：本帧写完，渲染方下次读到的是本帧结果
	cur_buf_ = 1 - cur_buf_;
}

// 阶段 1：推进轨迹
void ProjectileCore::phase_advance(float dt) {
	const int wb = 1 - cur_buf_;
	for (int i = 0; i < capacity_; ++i) {
		if (!(flags_[i] & P_ALIVE)) {
			continue;
		}
		// 引信期：**冻结移动**，只倒计时
		if (flags_[i] & P_FUSE_ARMED) {
			fuse_timer_[i] -= dt;
			px_[wb][i] = px_[cur_buf_][i];
			py_[wb][i] = py_[cur_buf_][i];
			pz_[wb][i] = pz_[cur_buf_][i];
			continue;
		}
		elapsed_[i] += dt;
		if (flags_[i] & P_ARC) {
			// 抛物线：水平线性插值 + 垂直 4h·t(1-t)
			const float t = std::min(elapsed_[i] / std::max(lifetime_[i], 0.01f), 1.0f);
			px_[wb][i] = arc_sx_[i] + (arc_lx_[i] - arc_sx_[i]) * t;
			pz_[wb][i] = arc_sz_[i] + (arc_lz_[i] - arc_sz_[i]) * t;
			py_[wb][i] = 4.0f * arc_h_[i] * t * (1.0f - t);
		} else {
			px_[wb][i] = px_[cur_buf_][i] + dx_[i] * speed_[i] * dt;
			pz_[wb][i] = pz_[cur_buf_][i] + dz_[i] * speed_[i] * dt;
			py_[wb][i] = py_[cur_buf_][i];
		}
	}
}

// 阶段 2：命中判定（点 vs 目标圆，**含 y 的 3D 距离**）
void ProjectileCore::phase_hit_test() {
	if (targets_.empty()) {
		return;
	}
	const int wb = 1 - cur_buf_;
	// 本帧新生成的小弹跳过本轮判定。
	//
	// 分裂出来的小弹生成在母弹位置（就在目标半径内）。若不跳过，它们会
	// 在同一轮循环里被再次检测、当场命中并消失——表现为"分裂了但看不到
	// 小弹"。当前靠"新 id 比当前索引大、循环还没走到"侥幸规避，但那是
	// **依赖 id 分配顺序的巧合**，池复用时就会失效。显式跳过才稳。
	const int mark = frame_spawn_mark_;
	// 收集本帧要处理的动作（不能在遍历中改池）
	std::vector<int> to_explode;
	std::vector<int> to_kill;

	for (int i = 0; i < capacity_; ++i) {
		if (!(flags_[i] & P_ALIVE)) {
			continue;
		}
		if (spawn_serial_[i] >= mark) {
			continue;              // 本帧新生成
		}
		flags_[i] &= ~P_BOUNCED;   // 每帧清弹射标记
		if (flags_[i] & P_FUSE_ARMED) {
			continue;              // 引信期不判定命中
		}
		const float bx = px_[wb][i];
		const float by = py_[wb][i];
		const float bz = pz_[wb][i];

		for (size_t t = 0; t < targets_.size(); ++t) {
			const Target &tg = targets_[t];
			if (tg.faction != faction_[i]) {
				continue;          // 阵营不符
			}
			if (already_hit(i, tg.ref)) {
				continue;          // 同一目标只结算一次
			}
			// 命中模型：**球（子弹）vs 竖直圆柱（目标）**。
			//
			// 不能简单地把子弹当质点、目标当球——那样 y 分量会吃掉横向容差：
			// 贴地飞的子弹在 y 上离"目标中心"固定差一截，命中半径被白白
			// 消耗掉（实测贴地弹要飞到目标正中心才判定命中）。
			//
			// 横向：圆心距 ≤ 目标半径 + 子弹半径
			// 纵向：子弹在 [地面-子弹半径, 目标高+子弹半径] 之内
			// 这样既保留了"贴地弹有横向容差"，也保留了
			//「弧线弹飞过头顶打不到」——超过目标高度就不算命中。
			const float ddx = bx - tg.x;
			const float ddz = bz - tg.z;
			const float dh2 = ddx * ddx + ddz * ddz;
			const float rr = tg.radius + BULLET_RADIUS;
			if (dh2 > rr * rr) {
				continue;
			}
			if (by < -BULLET_RADIUS || by > TARGET_HEIGHT + BULLET_RADIUS) {
				continue;          // 从头顶飞过 / 在地面以下
			}

			remember_hit(i, tg.ref);
			++hit_count_[i];

			// 分裂：以飞行方向为中心散射 N 枚小弹。
			// **只分裂一次**——否则小弹命中后继续分裂会无限繁殖。
			// 与旧实现同口径：小弹清零弹射/穿透、寿命 1.2 秒。
			if (split_count_[i] > 0 && !(flags_[i] & P_SPLIT_DONE)) {
				flags_[i] |= P_SPLIT_DONE;
				do_split(i);
			}

			// 发命中事件（伤害由 GDScript 结算）
			SimEvent ev;
			ev.type = EV_HIT;
			ev.id = i;
			ev.x = bx;
			ev.y = by;
			ev.z = bz;
			ev.target_id = tg.ref;
			ev.damage = damage_[i];
			ev.elem = elem_[i];
			ev.explode_radius = 0.0f;
			ev.explode_damage = 0.0f;
			// has_zone 挂在命中事件上：命中消失时也要在原地留区域
			//（策划「命中/有效期结束后原地生成区域」）。
			// **不要另外补发 expire**——那会让 GDScript 侧以为子弹是自然消散的。
			ev.has_zone = has_zone_[i];
			events_.push_back(ev);

			// 弹射：还有次数就转向继续飞（**不消失、不触发引信/落地区域**）
			if (bounces_left_[i] > 0) {
				--bounces_left_[i];
				flags_[i] |= P_BOUNCED;
				do_bounce(i);
				break;             // 本帧只处理一次命中
			}

			// 穿透：命中数未超上限就继续飞
			if (hit_count_[i] <= pierce_left_[i]) {
				break;
			}

			// 该消失了
			if (fuse_time_[i] > 0.0f) {
				to_explode.push_back(i);
			} else {
				to_kill.push_back(i);
			}
			break;
		}
	}

	for (size_t k = 0; k < to_explode.size(); ++k) {
		explode(to_explode[k]);
	}
	for (size_t k = 0; k < to_kill.size(); ++k) {
		// 命中后消失**不再补发 expire**：命中事件已经报告了这次交互，
		// 补发会让消费方以为子弹是自然消散的（实测多出一条事件）。
		// has_zone 已挂在命中事件上。
		despawn(to_kill[k]);
	}
}

// 阶段 3：到期回收
void ProjectileCore::phase_lifetime() {
	const int wb = 1 - cur_buf_;
	std::vector<int> to_explode;
	std::vector<int> to_kill;
	for (int i = 0; i < capacity_; ++i) {
		if (!(flags_[i] & P_ALIVE)) {
			continue;
		}
		// 引信到期 → 爆炸
		if ((flags_[i] & P_FUSE_ARMED) && fuse_timer_[i] <= 0.0f) {
			to_explode.push_back(i);
			continue;
		}
		if (elapsed_[i] >= lifetime_[i]) {
			if (fuse_time_[i] > 0.0f) {
				// 到期进入引信（先冻结，等倒计时）。
				//
				// **守卫必须判"未武装"**：本阶段每帧都会跑到这里，而进入
				// 引信后 elapsed_ 已不再增长、`elapsed >= lifetime` 恒成立。
				// 不判的话每帧都把计时器重置回满值，永远数不到 0
				//（实测引信永不爆炸）。
				if (!(flags_[i] & P_FUSE_ARMED)) {
					flags_[i] |= P_FUSE_ARMED;
					fuse_timer_[i] = fuse_time_[i];
					px_[wb][i] = px_[cur_buf_][i];
					py_[wb][i] = py_[cur_buf_][i];
					pz_[wb][i] = pz_[cur_buf_][i];
				}
			} else {
				to_kill.push_back(i);
			}
		}
	}
	for (size_t k = 0; k < to_explode.size(); ++k) {
		explode(to_explode[k]);
	}
	for (size_t k = 0; k < to_kill.size(); ++k) {
		emit(EV_EXPIRE, to_kill[k]);
		despawn(to_kill[k]);
	}
}

// 弹射：转向最近未命中目标；找不到则原路反向
void ProjectileCore::do_bounce(int id) {
	int best = -1;
	float best_d = 1e30f;
	const float bx = px_[cur_buf_][id];
	const float bz = pz_[cur_buf_][id];
	for (size_t t = 0; t < targets_.size(); ++t) {
		const Target &tg = targets_[t];
		if (tg.faction != faction_[id]) {
			continue;
		}
		if (already_hit(id, tg.ref)) {
			continue;
		}
		const float ddx = tg.x - bx;
		const float ddz = tg.z - bz;
		const float d = ddx * ddx + ddz * ddz;
		if (d < best_d) {
			best_d = d;
			best = static_cast<int>(t);
		}
	}
	if (best >= 0) {
		const Target &tg = targets_[best];
		float ux = tg.x - bx;
		float uz = tg.z - bz;
		const float len = std::sqrt(ux * ux + uz * uz);
		if (len > 1e-6f) {
			dx_[id] = ux / len;
			dz_[id] = uz / len;
		}
	} else {
		dx_[id] = -dx_[id];   // 原路反弹
		dz_[id] = -dz_[id];
	}
	// 弹射后重置寿命，保证能飞到新目标（与既有实现同口径）
	elapsed_[id] = 0.0f;
	lifetime_[id] = std::max(lifetime_[id], 1.5f);
	// 弧线弹弹射后改为直线（既有实现也是直接改 direction，不再走抛物线）
	flags_[id] &= ~P_ARC;
}

// 引信爆炸：半径内全部目标发事件（**不是单目标**）
void ProjectileCore::explode(int id) {
	const float bx = px_[cur_buf_][id];
	const float bz = pz_[cur_buf_][id];
	const float r = explode_radius_[id];
	SimEvent ev;
	ev.type = EV_EXPLODE;
	ev.id = id;
	ev.x = bx;
	ev.y = py_[cur_buf_][id];
	ev.z = bz;
	ev.target_id = -1;
	ev.damage = explode_damage_[id];
	ev.elem = elem_[id];
	ev.explode_radius = r;
	ev.explode_damage = explode_damage_[id];
	ev.has_zone = has_zone_[id];
	events_.push_back(ev);
	despawn(id);
}

// 分裂：以飞行方向为中心均匀散射 N 枚小弹。
//
// 与旧实现（Projectile._spawn_split）同口径：
//   · 方向在原方向 ±split_spread 内均匀展开
//   · 伤害 ×split_pct
//   · **清零弹射与穿透**（否则小弹会各自再弹射/穿透，数量失控）
//   · 寿命固定 1.2 秒
//   · 继承阵营与元素
void ProjectileCore::do_split(int id) {
	const int n = split_count_[id];
	if (n <= 0) {
		return;
	}
	// 基准方向
	const float bx = dx_[id];
	const float bz = dz_[id];
	const float base_ang = std::atan2(bz, bx);
	const float spread = split_spread_[id];
	for (int k = 0; k < n; ++k) {
		// 均匀展开：n=1 时取正前方；n>1 时在 [-spread, +spread] 上等分
		const float t = (n <= 1) ? 0.0f
			: (static_cast<float>(k) / static_cast<float>(n - 1)) * 2.0f - 1.0f;
		const float ang = base_ang + t * spread;
		SpawnDesc d;
		d.x = px_[cur_buf_][id];
		d.y = py_[cur_buf_][id];
		d.z = pz_[cur_buf_][id];
		d.dx = std::cos(ang);
		d.dz = std::sin(ang);
		d.speed = speed_[id];
		d.damage = damage_[id] * split_pct_[id];
		d.lifetime = 1.2f;
		d.elem = elem_[id];
		d.faction = faction_[id];
		d.pierce = 0;        // 小弹不穿透
		d.bounces = 0;       // 小弹不弹射
		d.arc = false;
		d.arc_height = 0.0f;
		d.fuse = 0.0f;
		d.explode_radius = 0.0f;
		d.explode_damage = 0.0f;
		d.split_count = 0;   // 小弹不再分裂
		d.split_pct = 0.0f;
		d.split_spread = 0.0f;
		d.has_zone = 0;
		spawn(d);
	}
}

void ProjectileCore::remember_hit(int id, int ref) {
	const int base = id * MAX_HIT_MEMORY;
	for (int k = 0; k < MAX_HIT_MEMORY; ++k) {
		if (hit_memory_[base + k] < 0) {
			hit_memory_[base + k] = ref;
			return;
		}
	}
	// 记忆满了：覆盖最旧的一个（极端情况，8 个目标够用）
	hit_memory_[base] = ref;
}

bool ProjectileCore::already_hit(int id, int ref) const {
	const int base = id * MAX_HIT_MEMORY;
	for (int k = 0; k < MAX_HIT_MEMORY; ++k) {
		if (hit_memory_[base + k] == ref) {
			return true;
		}
	}
	return false;
}

void ProjectileCore::emit(int type, int id) {
	SimEvent ev;
	ev.type = type;
	ev.id = id;
	ev.x = px_[cur_buf_][id];
	ev.y = py_[cur_buf_][id];
	ev.z = pz_[cur_buf_][id];
	ev.target_id = -1;
	ev.damage = damage_[id];
	ev.elem = elem_[id];
	ev.explode_radius = 0.0f;
	ev.explode_damage = 0.0f;
	ev.has_zone = has_zone_[id];
	events_.push_back(ev);
}

void ProjectileCore::drain_events(std::vector<SimEvent> &out) {
	out.swap(events_);
	events_.clear();
}

void ProjectileCore::fill_render_buffer(std::vector<float> &out, float base_scale) const {
	out.resize(static_cast<size_t>(capacity_) * 12);
	for (int i = 0; i < capacity_; ++i) {
		float *m = out.data() + i * 12;
		for (int k = 0; k < 12; ++k) {
			m[k] = 0.0f;
		}
		if (!(flags_[i] & P_ALIVE)) {
			// 未存活：缩放写 0 → MultiMesh 自动隐藏该实例
			continue;
		}
		// 引信期的子弹放大一点（提示"这个要炸了"）
		const float s = (flags_[i] & P_FUSE_ARMED) ? base_scale * 1.4f : base_scale;
		m[0] = s;
		m[5] = s;
		m[10] = s;
		m[3] = px_[cur_buf_][i];
		m[7] = py_[cur_buf_][i];
		m[11] = pz_[cur_buf_][i];
	}
}

} // namespace proj
