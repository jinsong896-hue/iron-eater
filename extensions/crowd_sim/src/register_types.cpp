// CrowdSim GDExtension 入口 —— 大规模敌人模拟系统
// 注册 CrowdSim 类（暴露给 GDScript）。
#include <godot_cpp/core/class_db.hpp>
#include "crowd_sim.h"

using namespace godot;

extern "C" {
// 与 crowd_sim.gdextension 的 entry_symbol 一致
GDExtensionBool GDE_EXPORT crowd_sim_library_init(
		const GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_crowd_sim_module);
	init_obj.register_terminator(uninitialize_crowd_sim_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}

void initialize_crowd_sim_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<CrowdSim>();
}

void uninitialize_crowd_sim_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}
