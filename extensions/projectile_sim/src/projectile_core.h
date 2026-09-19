#ifndef PROJECTILE_CORE_H
#define PROJECTILE_CORE_H

// ProjectileCore —— 纯 C++ 投射物模拟核（**不依赖任何 Godot 类型**）
//
// ## 与 CrowdSim 的关键差异：必须有 y 轴
// CrowdSim 的 SoA 刻意省掉了 y（「Y 轴恒为地面高度，省 1/3 带宽」）。
// 但投射物的弧线（抛物线）**必须有 y**：
//     base.y += 4.0 * height * t * (1.0 - t)
// 且命中判定也依赖 y —— 「弧线弹飞过头顶时打不到敌人」是既有行为，
// 重写时必须保留。故本核**独立于 CrowdSim**，自带 y 通道。
//
// ## 为什么不用空间哈希
// 子弹多（数千）但目标少（几十~数百）。每帧做 O(子弹 × 目标) 的线性扫描
// 是 4096 × 200 ≈ 82 万次距离判定，C++ 里亚毫秒级，比建哈希表还快。
// 等目标数真的上千再加哈希，现在加是过早优化。
//
// ## 为什么核只报事件、不算伤害
// 玩家侧的护盾/无敌帧/翻滚免疫/连击减伤/反射全在 GDScript。
// 核里算伤害必然算不准，且两套规则迟早分叉（表现是「同样的攻击
// 打节点怪和打子弹命中伤害不一样」）。故核只报「谁在何时命中了什么」，
// 伤害由 GDScript 走既有链路结算——与群体单位同一套思路。

#include <cstdint>
#include <vector>

namespace proj {

// 固定容量上限（池化，不动态增长）
constexpr int CAP = 4096;
// 每个子弹最多记住几个已命中目标（去重用）
constexpr int MAX_HIT_MEMORY = 8;
// 子弹碰撞球半径（与旧实现 Projectile 的 SphereShape3D 一致）
constexpr float BULLET_RADIUS = 0.3f;
// 目标高度（敌人胶囊从地面往上约 2 米）
constexpr float TARGET_HEIGHT = 2.0f;

// 实例标志位
enum SimFlags : uint32_t {
	P_ALIVE = 1u << 0,
	P_ARC = 1u << 1,          // 抛物线轨迹
	P_FUSE_ARMED = 1u << 2,   // 已进入引信倒计时（冻结移动）
	P_BOUNCED = 1u << 3,      // 本帧刚弹射过（防止同帧重复弹）
	P_SPLIT_DONE = 1u << 4,   // 已分裂过（**只分裂一次**，防无限繁殖）
};

// 阵营：决定打谁
enum Faction : int {
	FACTION_ENEMY = 0,   // 打敌人（玩家射出）
	FACTION_PLAYER = 1,  // 打玩家（敌人射出）
};

// 事件类型
enum EventType : int {
	EV_HIT = 0,       // 命中单个目标
	EV_EXPLODE = 1,   // 引信爆炸（范围）
	EV_EXPIRE = 2,    // 到期消失（可能带 zone_on_land）
};

// 导出给 GDScript 的事件
struct SimEvent {
	int type;
	int id;          // 子弹 id
	float x, y, z;   // 世界坐标
	int target_id;   // EV_HIT 时：命中的目标索引（-1 表示无）
	float damage;
	int elem;        // 元素枚举（-1 = 纯物理）
	// 引信爆炸时带上半径（GDScript 据此结算范围伤害）
	float explode_radius;
	float explode_damage;
	// 是否要在原地留区域（EV_EXPIRE 时用）
	int has_zone;
};

// 目标：一个圆（x/z/半径 + 阵营）。节点式敌人与群体单位都转成这个。
struct Target {
	float x, z, radius;
	int faction;
	int ref;         // 回调 GDScript 用的引用（节点索引或单位 id）
};

// 生成参数（从 GDScript 传入）
struct SpawnDesc {
	float x, y, z;              // 起点
	float dx, dz;               // 方向（已归一化，y 由弧线参数决定）
	float speed;
	float damage;
	float lifetime;
	int elem;                   // -1 = 纯物理
	int faction;
	int pierce;                 // 可穿透的额外目标数
	int bounces;                // 弹射次数
	bool arc;
	float arc_height;
	float fuse;                 // >0 = 到期后进入引信
	float explode_radius;
	float explode_damage;
	int split_count;
	float split_pct;
	float split_spread;
	int has_zone;
};

class ProjectileCore {
public:
	ProjectileCore();

	void setup(int capacity);
	void clear();

	// 生成一发子弹，返回 id（池满返回 -1）
	int spawn(const SpawnDesc &d);
	void despawn(int id);

	// 目标表：每帧由 GDScript 组装后喂入（节点式敌人 + 群体单位）
	void set_targets(const std::vector<Target> &targets);

	// 推进一帧
	void step(float dt);

	// 事件队列（取走即清空）
	void drain_events(std::vector<SimEvent> &out);

	// —— 查询 ——
	int capacity() const { return capacity_; }
	int active_count() const { return active_; }
	bool is_alive(int id) const;
	float pos_x(int id) const;
	float pos_y(int id) const;
	float pos_z(int id) const;
	float damage_of(int id) const;
	int elem_of(int id) const;
	int faction_of(int id) const;
	int pierce_left_of(int id) const;
	int bounces_left_of(int id) const;
	bool fuse_armed(int id) const;

	// 渲染缓冲：每实例 12 float（MultiMesh 3x4 行主序）
	void fill_render_buffer(std::vector<float> &out, float base_scale) const;

private:
	// 阶段
	void phase_advance(float dt);
	void phase_hit_test();
	void phase_lifetime();

	// 命中处理：返回是否该继续飞（弹射/穿透时不消失）
	bool on_hit(int id, int target_idx);
	// 弹射：转向最近未命中目标；找不到则原路反向
	void do_bounce(int id);
	// 分裂：以飞行方向为中心散射 N 枚小弹（**只分裂一次**）
	void do_split(int id);
	// 记下已命中（去重）
	void remember_hit(int id, int ref);
	bool already_hit(int id, int ref) const;
	// 引信爆炸：收集半径内全部目标发事件
	void explode(int id);

	void emit(int type, int id);

	int capacity_ = 0;
	int active_ = 0;
	std::vector<int> free_list_;

	// —— SoA 池 ——
	// 位置双缓冲（读 cur_，写 1-cur_）——**含 y**
	std::vector<float> px_[2];
	std::vector<float> py_[2];
	std::vector<float> pz_[2];
	std::vector<float> dx_;        // 方向 x（归一化）
	std::vector<float> dz_;        // 方向 z
	std::vector<float> speed_;
	std::vector<float> damage_;
	std::vector<float> lifetime_;
	std::vector<float> elapsed_;
	std::vector<int> elem_;
	std::vector<int> pierce_left_;
	std::vector<int> bounces_left_;
	std::vector<int> hit_count_;
	std::vector<int> faction_;
	std::vector<uint32_t> flags_;

	// 弧线参数
	std::vector<float> arc_sx_, arc_sz_;       // 起点
	std::vector<float> arc_lx_, arc_lz_;       // 落点
	std::vector<float> arc_h_;                 // 弧高

	// 引信
	std::vector<float> fuse_time_, fuse_timer_;
	std::vector<float> explode_radius_, explode_damage_;

	// 分裂
	std::vector<int> split_count_;
	std::vector<float> split_pct_, split_spread_;

	// 落地区域标记
	std::vector<int> has_zone_;

	// 去重：每个子弹一段固定长度，存已命中目标的 ref
	std::vector<int> hit_memory_;   // 长度 = capacity * MAX_HIT_MEMORY

	int cur_buf_ = 0;
	// 每发子弹的生成序号 + 本帧的序号门槛。
	// 序号 >= frame_spawn_mark_ 的是"本帧新生成"，跳过本轮命中判定
	//（见 phase_hit_test 的注释）。用序号而不是 id 区间——
	// 池复用会让 id 重复使用，id 区间判断不可靠。
	std::vector<int> spawn_serial_;
	int spawn_serial_next_ = 0;
	int frame_spawn_mark_ = 0;

	// 目标表（本帧）
	std::vector<Target> targets_;

	// 事件队列
	std::vector<SimEvent> events_;
};

} // namespace proj

#endif // PROJECTILE_CORE_H
