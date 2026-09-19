#include "crowd_sim.h"

#include "sim_core.h"

#include <cmath>

#include <godot_cpp/core/error_macros.hpp>

namespace godot {

void CrowdSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "capacity", "cell_size"), &CrowdSim::setup);
	ClassDB::bind_method(D_METHOD("set_obstacles", "aabbs"), &CrowdSim::set_obstacles);
	ClassDB::bind_method(D_METHOD("spawn", "x", "z", "hp", "speed", "radius", "scale"),
			&CrowdSim::spawn);
	ClassDB::bind_method(D_METHOD("despawn", "id"), &CrowdSim::despawn);
	ClassDB::bind_method(D_METHOD("step", "dt", "player_x", "player_z"), &CrowdSim::step);
	ClassDB::bind_method(D_METHOD("query_circle", "cx", "cz", "radius"), &CrowdSim::query_circle);
	ClassDB::bind_method(D_METHOD("query_cone", "ox", "oz", "dir_x", "dir_z",
			"half_angle", "range"), &CrowdSim::query_cone);
	ClassDB::bind_method(D_METHOD("set_attack_params", "range", "interval", "damage"),
			&CrowdSim::set_attack_params);
	ClassDB::bind_method(D_METHOD("apply_damage", "ids", "amount"), &CrowdSim::apply_damage);
	ClassDB::bind_method(D_METHOD("drain_events"), &CrowdSim::drain_events);
	ClassDB::bind_method(D_METHOD("get_render_buffer"), &CrowdSim::get_render_buffer);
	ClassDB::bind_method(D_METHOD("get_position_buffer"), &CrowdSim::get_position_buffer);
	ClassDB::bind_method(D_METHOD("get_active_count"), &CrowdSim::get_active_count);
	ClassDB::bind_method(D_METHOD("get_capacity"), &CrowdSim::get_capacity);
	ClassDB::bind_method(D_METHOD("is_alive", "id"), &CrowdSim::is_alive);
	ClassDB::bind_method(D_METHOD("get_position", "id"), &CrowdSim::get_position);
	ClassDB::bind_method(D_METHOD("get_hp", "id"), &CrowdSim::get_hp);
	ClassDB::bind_method(D_METHOD("set_stagger", "id", "seconds"), &CrowdSim::set_stagger);
	ClassDB::bind_method(D_METHOD("set_elite", "id", "elite"), &CrowdSim::set_elite);
	ClassDB::bind_method(D_METHOD("set_target", "id", "target_id"), &CrowdSim::set_target);
}

CrowdSim::CrowdSim() {
	core = new crowd::SimCore();
}

CrowdSim::~CrowdSim() {
	delete core;
	core = nullptr;
}

void CrowdSim::setup(int p_capacity, float p_cell_size) {
	core->setup(p_capacity, p_cell_size);
}

void CrowdSim::set_obstacles(const PackedFloat32Array &p_aabbs) {
	// 每 4 个 float 一个 AABB：min_x, min_z, max_x, max_z
	std::vector<crowd::AABB> obs;
	const int n = p_aabbs.size() / 4;
	obs.reserve(static_cast<size_t>(n));
	for (int i = 0; i < n; ++i) {
		crowd::AABB a;
		a.min_x = p_aabbs[i * 4 + 0];
		a.min_z = p_aabbs[i * 4 + 1];
		a.max_x = p_aabbs[i * 4 + 2];
		a.max_z = p_aabbs[i * 4 + 3];
		obs.push_back(a);
	}
	core->set_obstacles(obs);
}

int CrowdSim::spawn(float x, float z, float hp, float speed, float radius, float scale) {
	return core->spawn(x, z, hp, speed, radius, scale);
}

void CrowdSim::despawn(int id) {
	core->despawn(id);
}

void CrowdSim::step(float dt, float player_x, float player_z) {
	core->step(dt, player_x, player_z);
	// 模拟完成即交换双缓冲：渲染方下次 sync 读到的就是本帧结果。
	// （"下一帧完成上一帧"的异步时序由 GDScript 侧驱动，核本身是同步的）
	core->swap_buffers();
}

PackedInt32Array CrowdSim::query_circle(float cx, float cz, float radius) {
	std::vector<int> ids;
	core->query_circle(cx, cz, radius, ids);
	PackedInt32Array out;
	out.resize(static_cast<int>(ids.size()));
	for (size_t i = 0; i < ids.size(); ++i) {
		out[static_cast<int>(i)] = ids[i];
	}
	return out;
}

PackedInt32Array CrowdSim::query_cone(float ox, float oz, float dir_x, float dir_z,
		float half_angle, float range) {
	std::vector<int> ids;
	const float cos_half = std::cos(half_angle);
	core->query_cone(ox, oz, dir_x, dir_z, cos_half, range, ids);
	PackedInt32Array out;
	out.resize(static_cast<int>(ids.size()));
	for (size_t i = 0; i < ids.size(); ++i) {
		out[static_cast<int>(i)] = ids[i];
	}
	return out;
}

int CrowdSim::apply_damage(const PackedInt32Array &ids, float amount) {
	std::vector<int> v;
	v.reserve(static_cast<size_t>(ids.size()));
	for (int i = 0; i < ids.size(); ++i) {
		v.push_back(ids[i]);
	}
	return core->apply_damage(v, amount);
}

Array CrowdSim::drain_events() {
	std::vector<crowd::SimEvent> evs;
	core->drain_events(evs);
	Array out;
	for (const crowd::SimEvent &e : evs) {
		Dictionary d;
		// 事件类型用字符串——GDScript 侧按字符串分支最直观，
		// 也避免两边各维护一份枚举常量表而漂移。
		d["type"] = (e.type == crowd::SIM_EVENT_ATTACK) ? "attack" : "death";
		d["id"] = e.id;
		d["pos"] = Vector3(e.x, 0.0f, e.z);
		d["is_elite"] = e.is_elite != 0;
		d["damage"] = e.damage;
		out.push_back(d);
	}
	return out;
}


void CrowdSim::set_attack_params(float range, float interval, float damage) {
	core->set_attack_params(range, interval, damage);
}

PackedFloat32Array CrowdSim::get_render_buffer() const {
	// 每实例 12 个 float（MultiMesh 3D 的 transform 是 3x4 矩阵）：
	// [0..11] = 行主序 3x4；末列写世界坐标，对角写缩放。
	// 这样 GDScript 侧直接 multimesh_set_buffer 就能画。
	PackedFloat32Array buf;
	const int cap = core->capacity();
	buf.resize(cap * 12);
	float *w = buf.ptrw();
	for (int i = 0; i < cap; ++i) {
		float *m = w + i * 12;
		for (int k = 0; k < 12; ++k) {
			m[k] = 0.0f;
		}
		if (!core->is_alive(i)) {
			// 未存活：缩放写 0 → MultiMesh 不渲染该实例（无需重建 buffer）
			m[0] = 0.0f;
			m[5] = 0.0f;
			m[10] = 0.0f;
			continue;
		}
		const float s = core->scale_of(i);
		m[0] = s;
		m[5] = s;
		m[10] = s;
		m[3] = core->pos_x(i);
		m[7] = 0.0f;
		m[11] = core->pos_z(i);
	}
	return buf;
}

PackedFloat32Array CrowdSim::get_position_buffer() const {
	// 只返回**存活**的单位（紧凑排列），每 4 个 float = x, z, id, 1.0。
	// 末尾的 1.0 是占位（保持 4 对齐），便于 GDScript 侧直接喂给
	// ProjectileSim.set_targets 的 targets 数组格式。
	PackedFloat32Array out;
	const int cap = core->capacity();
	// 先数活跃数，一次分配到位（避免反复 resize）
	int n = 0;
	for (int i = 0; i < cap; ++i) {
		if (core->is_alive(i)) {
			++n;
		}
	}
	out.resize(n * 4);
	float *w = out.ptrw();
	int k = 0;
	for (int i = 0; i < cap; ++i) {
		if (!core->is_alive(i)) {
			continue;
		}
		w[k * 4 + 0] = core->pos_x(i);
		w[k * 4 + 1] = core->pos_z(i);
		w[k * 4 + 2] = static_cast<float>(i);   // ref（回调 GDScript 用）
		w[k * 4 + 3] = 1.0f;
		++k;
	}
	return out;
}

int CrowdSim::get_active_count() const {
	return core->active_count();
}

int CrowdSim::get_capacity() const {
	return core->capacity();
}

bool CrowdSim::is_alive(int id) const {
	return core->is_alive(id);
}

Vector3 CrowdSim::get_position(int id) const {
	if (!core->is_alive(id)) {
		return Vector3();
	}
	return Vector3(core->pos_x(id), 0.0f, core->pos_z(id));
}

float CrowdSim::get_hp(int id) const {
	return core->hp_of(id);
}

void CrowdSim::set_stagger(int id, float seconds) {
	core->set_stagger(id, seconds);
}

void CrowdSim::set_elite(int id, bool elite) {
	core->set_elite_flag(id, elite);
}

void CrowdSim::set_target(int id, int target_id) {
	core->set_target(id, target_id);
}

} // namespace godot
