#include "gnc_local_health.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
using namespace godot;

static void initialize_gnc_health(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(GncLocalHealth);
    }
}
static void uninitialize_gnc_health(ModuleInitializationLevel level) {
    (void)level;
}
extern "C" {
GDExtensionBool GDE_EXPORT gnc_health_gdextension_init(
        GDExtensionInterfaceGetProcAddress get_proc_address,
        const GDExtensionClassLibraryPtr library,
        GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_gnc_health);
    init.register_terminator(uninitialize_gnc_health);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
