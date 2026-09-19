#ifndef PROJECTILE_SIM_H
#define PROJECTILE_SIM_H

// ProjectileSim —— 投射物模拟（GDScript 绑定层）
//
// 与 CrowdSim 同架构：本类是**薄绑定**，所有模拟逻辑在 proj::ProjectileCore
// （纯 C++，不依赖 Godot）。这样核能独立编译/基准测试，换后端也不影响调用方。

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace proj {
class ProjectileCore;
}

namespace godot {

class ProjectileSim : public Node {
	GDCLASS(ProjectileSim, Node)

private:
	proj::ProjectileCore *core = nullptr;
	float base_scale_ = 1.0f;

protected:
	static void _bind_methods();

public:
	ProjectileSim();
	~ProjectileSim();

	void setup(int p_capacity);
	void clear();

	// 生成：参数用 Dictionary 传（字段多，逐个列参数太笨重且易错位）
	int spawn(const Dictionary &p_desc);
	void despawn(int p_id);

	// 目标表：每 4 个 float = x, z, radius, ref（faction 另用整数数组）
	void set_targets(const PackedFloat32Array &p_targets,
			const PackedInt32Array &p_factions);
	void clear_targets();

	void step(float p_dt);
	Array drain_events();

	// 渲染
	PackedFloat32Array get_render_buffer() const;
	void set_base_scale(float p_scale);

	// 查询
	int get_active_count() const;
	int get_capacity() const;
	bool is_alive(int p_id) const;
	Vector3 get_position(int p_id) const;
	float get_damage(int p_id) const;
	int get_elem(int p_id) const;
	int get_pierce_left(int p_id) const;
	int get_bounces_left(int p_id) const;
	bool is_fuse_armed(int p_id) const;
};

} // namespace godot

#endif // PROJECTILE_SIM_H
