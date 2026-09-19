#include "projectile_sim.h"

#include "projectile_core.h"

namespace godot {

void ProjectileSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "capacity"), &ProjectileSim::setup);
	ClassDB::bind_method(D_METHOD("clear"), &ProjectileSim::clear);
	ClassDB::bind_method(D_METHOD("spawn", "desc"), &ProjectileSim::spawn);
	ClassDB::bind_method(D_METHOD("despawn", "id"), &ProjectileSim::despawn);
	ClassDB::bind_method(D_METHOD("set_targets", "targets", "factions"),
			&ProjectileSim::set_targets);
	ClassDB::bind_method(D_METHOD("clear_targets"), &ProjectileSim::clear_targets);
	ClassDB::bind_method(D_METHOD("step", "dt"), &ProjectileSim::step);
	ClassDB::bind_method(D_METHOD("drain_events"), &ProjectileSim::drain_events);
	ClassDB::bind_method(D_METHOD("get_render_buffer"), &ProjectileSim::get_render_buffer);
	ClassDB::bind_method(D_METHOD("set_base_scale", "scale"), &ProjectileSim::set_base_scale);
	ClassDB::bind_method(D_METHOD("get_active_count"), &ProjectileSim::get_active_count);
	ClassDB::bind_method(D_METHOD("get_capacity"), &ProjectileSim::get_capacity);
	ClassDB::bind_method(D_METHOD("is_alive", "id"), &ProjectileSim::is_alive);
	ClassDB::bind_method(D_METHOD("get_position", "id"), &ProjectileSim::get_position);
	ClassDB::bind_method(D_METHOD("get_damage", "id"), &ProjectileSim::get_damage);
	ClassDB::bind_method(D_METHOD("get_elem", "id"), &ProjectileSim::get_elem);
	ClassDB::bind_method(D_METHOD("get_pierce_left", "id"), &ProjectileSim::get_pierce_left);
	ClassDB::bind_method(D_METHOD("get_bounces_left", "id"), &ProjectileSim::get_bounces_left);
	ClassDB::bind_method(D_METHOD("is_fuse_armed", "id"), &ProjectileSim::is_fuse_armed);
}

ProjectileSim::ProjectileSim() {
	core = new proj::ProjectileCore();
}

ProjectileSim::~ProjectileSim() {
	delete core;
	core = nullptr;
}

void ProjectileSim::setup(int p_capacity) {
	core->setup(p_capacity);
}

void ProjectileSim::clear() {
	core->clear();
}

int ProjectileSim::spawn(const Dictionary &p_desc) {
	proj::SpawnDesc d;
	// 位置
	d.x = float(p_desc.get("x", 0.0));
	d.y = float(p_desc.get("y", 0.0));
	d.z = float(p_desc.get("z", 0.0));
	// 方向（只取 x/z）
	d.dx = float(p_desc.get("dx", 0.0));
	d.dz = float(p_desc.get("dz", 1.0));
	d.speed = float(p_desc.get("speed", 10.0));
	d.damage = float(p_desc.get("damage", 10.0));
	d.lifetime = float(p_desc.get("lifetime", 2.0));
	d.elem = int(p_desc.get("elem", -1));
	d.faction = int(p_desc.get("faction", 0));
	d.pierce = int(p_desc.get("pierce", 0));
	d.bounces = int(p_desc.get("bounces", 0));
	d.arc = bool(p_desc.get("arc", false));
	d.arc_height = float(p_desc.get("arc_height", 3.0));
	d.fuse = float(p_desc.get("fuse", 0.0));
	d.explode_radius = float(p_desc.get("explode_radius", 0.0));
	d.explode_damage = float(p_desc.get("explode_damage", 0.0));
	d.split_count = int(p_desc.get("split_count", 0));
	d.split_pct = float(p_desc.get("split_pct", 0.4));
	d.split_spread = float(p_desc.get("split_spread", 0.5));
	d.has_zone = int(p_desc.get("has_zone", 0));
	return core->spawn(d);
}

void ProjectileSim::despawn(int p_id) {
	core->despawn(p_id);
}

void ProjectileSim::set_targets(const PackedFloat32Array &p_targets,
		const PackedInt32Array &p_factions) {
	std::vector<proj::Target> out;
	const int n = p_targets.size() / 4;
	out.reserve(static_cast<size_t>(n));
	for (int i = 0; i < n; ++i) {
		proj::Target t;
		t.x = p_targets[i * 4 + 0];
		t.z = p_targets[i * 4 + 1];
		t.radius = p_targets[i * 4 + 2];
		t.ref = static_cast<int>(p_targets[i * 4 + 3]);
		t.faction = (i < p_factions.size()) ? p_factions[i] : 0;
		out.push_back(t);
	}
	core->set_targets(out);
}

void ProjectileSim::clear_targets() {
	std::vector<proj::Target> empty;
	core->set_targets(empty);
}

void ProjectileSim::step(float p_dt) {
	core->step(p_dt);
}

Array ProjectileSim::drain_events() {
	std::vector<proj::SimEvent> evs;
	core->drain_events(evs);
	Array out;
	for (size_t i = 0; i < evs.size(); ++i) {
		const proj::SimEvent &e = evs[i];
		Dictionary d;
		// 类型用字符串：GDScript 侧按字符串分支最直观，
		// 也避免两边各维护一份枚举常量表而漂移。
		switch (e.type) {
			case proj::EV_HIT: d["type"] = "hit"; break;
			case proj::EV_EXPLODE: d["type"] = "explode"; break;
			default: d["type"] = "expire"; break;
		}
		d["id"] = e.id;
		d["pos"] = Vector3(e.x, e.y, e.z);
		d["target_id"] = e.target_id;
		d["damage"] = e.damage;
		d["elem"] = e.elem;
		d["explode_radius"] = e.explode_radius;
		d["explode_damage"] = e.explode_damage;
		d["has_zone"] = e.has_zone != 0;
		out.push_back(d);
	}
	return out;
}

PackedFloat32Array ProjectileSim::get_render_buffer() const {
	std::vector<float> buf;
	core->fill_render_buffer(buf, base_scale_);
	PackedFloat32Array out;
	out.resize(static_cast<int>(buf.size()));
	float *w = out.ptrw();
	for (size_t i = 0; i < buf.size(); ++i) {
		w[i] = buf[i];
	}
	return out;
}

void ProjectileSim::set_base_scale(float p_scale) {
	base_scale_ = p_scale;
}

int ProjectileSim::get_active_count() const {
	return core->active_count();
}

int ProjectileSim::get_capacity() const {
	return core->capacity();
}

bool ProjectileSim::is_alive(int p_id) const {
	return core->is_alive(p_id);
}

Vector3 ProjectileSim::get_position(int p_id) const {
	if (!core->is_alive(p_id)) {
		return Vector3();
	}
	return Vector3(core->pos_x(p_id), core->pos_y(p_id), core->pos_z(p_id));
}

float ProjectileSim::get_damage(int p_id) const {
	return core->damage_of(p_id);
}

int ProjectileSim::get_elem(int p_id) const {
	return core->elem_of(p_id);
}

int ProjectileSim::get_pierce_left(int p_id) const {
	return core->pierce_left_of(p_id);
}

int ProjectileSim::get_bounces_left(int p_id) const {
	return core->bounces_left_of(p_id);
}

bool ProjectileSim::is_fuse_armed(int p_id) const {
	return core->fuse_armed(p_id);
}

} // namespace godot
