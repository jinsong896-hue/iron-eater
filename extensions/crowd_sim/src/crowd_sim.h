#ifndef CROWD_SIM_H
#define CROWD_SIM_H

// CrowdSim —— 大规模敌人模拟（GDScript 绑定层）
//
// 本类是**薄绑定**：所有模拟逻辑在 crowd::SimCore（纯 C++，不依赖 Godot），
// 这里只做「GDScript 类型 ↔ 原生类型」的转换与 ClassDB 注册。
// 这样切分的好处：模拟核能独立编译/基准测试，且换后端不影响调用方。

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace crowd {
class SimCore;
}

namespace godot {

class CrowdSim : public Node {
	GDCLASS(CrowdSim, Node)

private:
	crowd::SimCore *core = nullptr;

protected:
	static void _bind_methods();

public:
	CrowdSim();
	~CrowdSim();

	void setup(int p_capacity, float p_cell_size = 2.0f);
	void set_obstacles(const PackedFloat32Array &p_aabbs);
	int spawn(float x, float z, float hp, float speed, float radius, float scale);
	void despawn(int id);
	void step(float dt, float player_x, float player_z);

	PackedInt32Array query_circle(float cx, float cz, float radius);
	PackedInt32Array query_cone(float ox, float oz, float dir_x, float dir_z,
			float half_angle, float range);
	int apply_damage(const PackedInt32Array &ids, float amount);
	Array drain_events();

	PackedFloat32Array get_render_buffer() const;
	int get_active_count() const;
	int get_capacity() const;
	bool is_alive(int id) const;
	Vector3 get_position(int id) const;
	float get_hp(int id) const;
	void set_stagger(int id, float seconds);
	void set_elite(int id, bool elite);
	void set_target(int id, int target_id);
};

} // namespace godot

void initialize_crowd_sim_module(godot::ModuleInitializationLevel p_level);
void uninitialize_crowd_sim_module(godot::ModuleInitializationLevel p_level);

#endif // CROWD_SIM_H
