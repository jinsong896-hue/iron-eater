#ifndef CROWD_SIM_CORE_H
#define CROWD_SIM_CORE_H

// SimCore —— 纯 C++ 模拟核（**不依赖任何 Godot 类型**）
//
// 设计要点（对应实施计划「批次 1」）：
//   · SoA 固定容量池 + free_list，运行期零堆分配
//   · 位置双缓冲：step 读 A 写 B，渲染永远读"已完成"的那份
//   · 邻居查找走六步空间哈希流水线（照搬参考项目 GridSearch2D 的思路：
//     bounding_box → assign_and_count(原子计数) → prefix_sum →
//     place(原子 fetch-add 拿槽位) → fill_cell_start_end → 就绪）
//   · 障碍用 AABB 暴力判定（房间墙 <200 个，比建树划算）
//   · 移动 = 邻居斥力 + 朝目标的期望速度 + 转向插值
//
// Y 轴恒为地面高度，故只存 x/z 两个分量（省 1/3 带宽）。

#include <cstdint>
#include <vector>

#include "thread_pool.h"

namespace crowd {

// 固定容量上限（池化，不动态增长）
constexpr int CAP = 2048;
// 空间哈希格子数上限（网格维度会按包围盒裁剪到这个范围内）
constexpr int MAX_CELLS = 8192;

// 单个实例的存活标志位
enum SimFlags : uint32_t {
	SIM_ALIVE = 1u << 0,
	SIM_ELITE = 1u << 1,
	SIM_STAGGERED = 1u << 2,   // 硬直中：本帧不主动移动
};

// 轴对齐障碍盒（房间墙）
struct AABB {
	float min_x, min_z, max_x, max_z;
};

// 死亡/命中事件（导出给 GDScript 消费）
struct SimEvent {
	int type;      // 0 = death, 1 = attack
	int id;
	float x, z;
	int is_elite;
	float damage;  // 仅 type=1（attack）有意义
};

// 事件类型
enum SimEventType : int {
	SIM_EVENT_DEATH = 0,
	SIM_EVENT_ATTACK = 1,
};

class SimCore {
public:
	SimCore();

	void setup(int capacity, float cell_size);
	void set_obstacles(const std::vector<AABB> &obstacles);

	// 返回新实例 id；池满返回 -1
	int spawn(float x, float z, float hp, float speed, float radius, float scale);
	void despawn(int id);

	// 一帧模拟。player_x/player_z 是"跟随目标"。
	// 读 cur_buf_，写 1-cur_buf_，结束后由调用方 swap。
	void step(float dt, float player_x, float player_z);

	// 攻击参数（全体统一；个体差异后续按怪物类型扩展）
	//   进入 attack_range 后每 attack_interval 秒对玩家造成一次 attack_damage
	void set_attack_params(float range, float interval, float damage) {
		attack_range_ = range;
		attack_interval_ = interval > 0.0f ? interval : 1.0f;
		attack_damage_ = damage;
	}

	// 交换双缓冲（渲染方在 step 完成后调）
	void swap_buffers() { cur_buf_ = 1 - cur_buf_; }

	int read_buffer() const { return cur_buf_; }
	int write_buffer() const { return 1 - cur_buf_; }

	// —— 查询 ——
	// 圆查询：返回实例 id 列表
	void query_circle(float cx, float cz, float radius, std::vector<int> &out) const;
	// 锥形查询：origin + 朝向(dir_x,dir_z) + 半角(cos) + 射程
	void query_cone(float ox, float oz, float dir_x, float dir_z,
			float cos_half_angle, float range, std::vector<int> &out) const;

	// 批量伤害，返回击杀数
	int apply_damage(const std::vector<int> &ids, float amount);

	// 取走并清空事件队列
	void drain_events(std::vector<SimEvent> &out);

	// —— 单体访问 ——
	bool is_alive(int id) const;
	float pos_x(int id) const { return px_[cur_buf_][id]; }
	float pos_z(int id) const { return pz_[cur_buf_][id]; }
	float hp_of(int id) const { return hp_[id]; }
	float scale_of(int id) const { return scale_[id]; }
	void set_stagger(int id, float seconds);
	void set_elite_flag(int id, bool elite);
	void set_target(int id, int target_id);

	int capacity() const { return capacity_; }
	int active_count() const { return active_; }
	float cell_size() const { return cell_size_; }

private:
	// 六步流水线
	void build_hash();
	void phase_steer(float dt, float player_x, float player_z);
	void phase_collide_obstacles();
	void phase_integrate(float dt);
	// 攻击：进入距离的单位按间隔对玩家造成伤害（发事件，由 GDScript 结算）
	void phase_attack(float dt, float player_x, float player_z);

	// 空间哈希：把世界坐标映射到格子下标
	int cell_of(float x, float z) const;
	int cell_x(float x) const;
	int cell_z(float z) const;

	int capacity_ = 0;
	float cell_size_ = 2.0f;

	// —— SoA 池 ——
	// 位置双缓冲：读 cur_buf_，写 1-cur_buf_
	std::vector<float> px_[2];
	std::vector<float> pz_[2];
	std::vector<float> vx_;
	std::vector<float> vz_;
	std::vector<float> hp_;
	std::vector<float> max_hp_;
	std::vector<float> speed_;
	std::vector<float> radius_;
	std::vector<float> scale_;
	std::vector<float> stagger_;      // 剩余硬直时间
	std::vector<float> atk_cd_;       // 攻击冷却剩余（<=0 可攻击）
	std::vector<uint32_t> flags_;
	std::vector<int> target_id_;      // -1 = 跟随玩家

	// —— 攻击参数（全体统一）——
	float attack_range_ = 1.4f;
	float attack_interval_ = 1.2f;
	float attack_damage_ = 8.0f;

	int cur_buf_ = 0;
	int active_ = 0;
	std::vector<int> free_list_;

	// —— 空间哈希工作区 ——
	std::vector<int> hash_of_;        // 每个实例所在格子
	std::vector<int> sorted_ids_;     // 按格子排序后的实例 id
	std::vector<int> counts_;         // 每格计数（前缀和后变成起始偏移）
	std::vector<int> cell_start_;
	std::vector<int> cell_end_;
	int grid_w_ = 0;
	int grid_h_ = 0;
	float origin_x_ = 0.0f;
	float origin_z_ = 0.0f;
	int cell_count_ = 0;

	std::vector<AABB> obstacles_;
	std::vector<SimEvent> events_;

	ThreadPool pool_;
};

} // namespace crowd

#endif // CROWD_SIM_CORE_H
