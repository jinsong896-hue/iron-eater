#ifndef CROWD_SIM_H
#define CROWD_SIM_H

// CrowdSim —— 大规模敌人模拟（GDScript 绑定层）
//
// 批次 0 验证壳：只暴露 ping()/get_capacity()，证明编译链与 ClassDB 探测通畅。
// 批次 1 在此装入 SimCore（SoA 池 + 六步哈希流水线 + 双缓冲）。

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

class CrowdSim : public Node {
	GDCLASS(CrowdSim, Node)

private:
	int capacity = 0;

protected:
	static void _bind_methods();

public:
	CrowdSim();
	~CrowdSim();

	// 初始化容量（批次 1 将装入完整 SoA 池）
	void setup(int p_capacity);
	// 探活：返回传入值 + 1（验证跨语言调用真的通了）
	int ping(int value) const;
	int get_capacity() const;
};

} // namespace godot

void initialize_crowd_sim_module(godot::ModuleInitializationLevel p_level);
void uninitialize_crowd_sim_module(godot::ModuleInitializationLevel p_level);

#endif // CROWD_SIM_H
