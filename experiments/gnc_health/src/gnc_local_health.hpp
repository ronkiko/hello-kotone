#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
namespace godot {
class GncLocalHealth : public RefCounted {
    GDCLASS(GncLocalHealth, RefCounted)
protected:
    static void _bind_methods();
public:
    int64_t abi_version() const;
    int64_t local_health(int64_t nonce) const;
};
}
