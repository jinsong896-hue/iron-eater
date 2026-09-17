#include "crowd_sim.h"

namespace godot {

void CrowdSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "capacity"), &CrowdSim::setup);
	ClassDB::bind_method(D_METHOD("ping", "value"), &CrowdSim::ping);
	ClassDB::bind_method(D_METHOD("get_capacity"), &CrowdSim::get_capacity);
}

CrowdSim::CrowdSim() {}
CrowdSim::~CrowdSim() {}

void CrowdSim::setup(int p_capacity) {
	capacity = p_capacity > 0 ? p_capacity : 0;
}

int CrowdSim::ping(int value) const {
	return value + 1;
}

int CrowdSim::get_capacity() const {
	return capacity;
}

} // namespace godot
