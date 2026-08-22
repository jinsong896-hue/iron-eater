# GDExtension — Godot 4.x Research Digest (for the `gdextension` skill)

> Gathered 2026-05-29 from official Godot docs + godot-rust community docs to ground the v1.9.0
> `gdextension` skill. Sources: `tutorials/scripting/cpp/gdextension_cpp_example.rst` (verbatim),
> `gdextension/what_is_gdextension.html`, `gdextension/gdextension_file.html`, `gdextension/index.html`;
> community: godot-rust/gdext README + book.
>
> **Doc-layout note:** the C++ example lives under `tutorials/scripting/cpp/`. The SConstruct is NOT
> inlined in the tutorial — it's a downloadable file (`files/cpp_example/SConstruct`).

## 1. What it is & when to use it

- GDExtension lets the engine interact with **native shared libraries at runtime** — run native code
  **without recompiling the engine** (the key advantage over C++ *modules*, which compile into Godot and
  require shipping a custom engine binary).
- "More complicated to use than GDScript and C#." Use for: performance-critical native code, wrapping
  third-party C/C++ libraries, or building language bindings — distributable against a **stock** Godot.
- Mechanisms: `gdextension_interface.h` (C ABI), `extension_api.json` (exposed API), `*.gdextension` (load config).
- Languages: **godot-cpp (C++, official)** + community bindings (Rust — see §6).

## 2. Project / build setup

```bash
mkdir gdextension_cpp_example && cd gdextension_cpp_example
git init
git submodule add -b 4.x https://github.com/godotengine/godot-cpp
cd godot-cpp && git submodule update --init
```
**Branch rule:** the godot-cpp branch MUST match the target engine version (use `4.1` branch for Godot 4.1,
etc.). The tutorial's `4.x` is a placeholder to replace.

Layout:
```
gdextension_cpp_example/
├── project/                 # demo game to test the extension
│   ├── main.tscn
│   └── bin/gdexample.gdextension
├── godot-cpp/               # C++ bindings (submodule)
└── src/
    ├── register_types.{h,cpp}
    └── gdexample.{h,cpp}
```
Build: `scons platform=<platform>` (omit platform → current). Default = **debug**. SCons is the official path;
godot-cpp also ships CMake.

## 3. The `.gdextension` file

`[configuration]`:
- `entry_symbol` (String) — must match the exported C symbol (C++: `"example_library_init"`; gdext: `"gdext_rust_init"`).
- `compatibility_minimum` (String) — lowest supported engine version.
- `compatibility_maximum` (String) — locks out newer engines.
- `reloadable` (Bool) — hot reload on recompile (debug builds only).
- `android_aar_plugin` (Bool) — native libs exported by an Android plugin's AAR.

`[libraries]` — feature-tag key → binary path (relative to file or `res://`). Verbatim:
```ini
[configuration]
entry_symbol = "example_library_init"
compatibility_minimum = "4.1"
reloadable = true

[libraries]
macos.debug = "./libgdexample.macos.template_debug.dylib"
macos.release = "./libgdexample.macos.template_release.dylib"
windows.debug.x86_64 = "./gdexample.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "./gdexample.windows.template_release.x86_64.dll"
linux.debug.x86_64 = "./libgdexample.linux.template_debug.x86_64.so"
linux.release.x86_64 = "./libgdexample.linux.template_release.x86_64.so"
```
`[icons]`: `GDExample = "res://icons/gd_example.svg"` (per-node editor icon).
`[dependencies]`: extra libs to copy on export, keyed by platform, `source : export_subdir`.

## 4. Binding a class in C++ (verbatim essentials)

`gdexample.h`:
```cpp
#pragma once
#include <godot_cpp/classes/sprite2d.hpp>
namespace godot {
class GDExample : public Sprite2D {
    GDCLASS(GDExample, Sprite2D)
private:
    double time_passed; double amplitude; double speed; double time_emit;
protected:
    static void _bind_methods();
public:
    GDExample(); ~GDExample();
    void _process(double delta) override;
    void set_amplitude(const double p_amplitude); double get_amplitude() const;
    void set_speed(const double p_speed); double get_speed() const;
};
}
```
`gdexample.cpp` — `_bind_methods` binding patterns:
```cpp
void GDExample::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_amplitude"), &GDExample::get_amplitude);
    ClassDB::bind_method(D_METHOD("set_amplitude", "p_amplitude"), &GDExample::set_amplitude);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "amplitude"), "set_amplitude", "get_amplitude");

    ClassDB::bind_method(D_METHOD("get_speed"), &GDExample::get_speed);
    ClassDB::bind_method(D_METHOD("set_speed", "p_speed"), &GDExample::set_speed);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speed", PROPERTY_HINT_RANGE, "0,20,0.01"),
                 "set_speed", "get_speed");

    ADD_SIGNAL(MethodInfo("position_changed",
               PropertyInfo(Variant::OBJECT, "node"),
               PropertyInfo(Variant::VECTOR2, "new_pos")));
}
```
- Method: `ClassDB::bind_method(D_METHOD("name","arg"), &Class::method);`
- Property: `ADD_PROPERTY(PropertyInfo(Variant::FLOAT,"amplitude"), "set_amplitude","get_amplitude");` (bind getter/setter first)
- Property hint: `PropertyInfo(Variant::FLOAT,"speed", PROPERTY_HINT_RANGE, "0,20,0.01")`
- Signal: `ADD_SIGNAL(MethodInfo("position_changed", PropertyInfo(...), ...));` → emit `emit_signal("position_changed", this, new_position);`
- Virtual override: `void _process(double delta) override;`

`register_types.cpp` (entry point):
```cpp
void initialize_example_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    GDREGISTER_CLASS(GDExample);
}
void uninitialize_example_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}
extern "C" {
GDExtensionBool GDE_EXPORT example_library_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    const GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_example_module);
    init_obj.register_terminator(uninitialize_example_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
```
The exported `extern "C"` symbol name must equal `entry_symbol`. Register classes with `GDREGISTER_CLASS`,
gated on `MODULE_INITIALIZATION_LEVEL_SCENE`.

## 5. Using from editor / GDScript

- After build + placing `.gdextension` in `project/bin/`, the native class appears as a normal node type.
- Bound properties show in the Inspector (range hint → slider); signals show in the Node dock (Connect).
- Handler (verbatim):
```gdscript
extends Node
func _on_Sprite2D_position_changed(node, new_pos):
    print("The position of " + node.get_class() + " is now " + str(new_pos))
```
- Connect another node's signal from C++: `some_other_node->connect("the_signal", Callable(this, "my_method"));`

## 6. Rust alternative — godot-rust / gdext (COMMUNITY, not official)

MPL-2.0; min **Godot 4.2** for maintained releases. `Cargo.toml`: `crate-type = ["cdylib"]`, `godot = "0.x.y"`.
```rust
use godot::prelude::*;
struct MyExtension;
#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}

#[derive(GodotClass)]
#[class(init, base=Sprite2D)]
struct Player {
    base: Base<Sprite2D>,
    #[init(val = 100)] hitpoints: i32,
}
#[godot_api]
impl ISprite2D for Player {
    fn ready(&mut self) { godot_print!("Player ready!"); }
}
#[godot_api]
impl Player {
    #[func] fn take_damage(&mut self, damage: i32) {}
    #[signal] fn got_message();
}
```
`.gdextension` uses `entry_symbol = "gdext_rust_init"`. Since 4.2, gdext extensions load on any Godot where
runtime version >= API version.

## 7. Debugging native code

- **Hot reload:** `reloadable = true` reloads on recompile without editor restart — **debug builds only**.
- Debug vs release distinguished by `template_debug`/`template_release` `[libraries]` keys.
- No GDB/LLDB walkthrough in the tutorial — attaching a native debugger to the Godot process is the implied path.

## 8. Gotchas

- **godot-cpp branch must match engine version** (`4.x` is a placeholder).
- **Forward-but-not-backward compat:** extension targeting 4.2 works in 4.3, NOT vice-versa. **Exception:**
  extensions targeting 4.0 do NOT work in 4.1+.
- `compatibility_minimum` must reflect lowest supported version; too low → runtime load failure.
- `entry_symbol` mismatch → won't load.
- `[libraries]` path/arch mistakes → silent failure on that platform.
- Hot reload needs debug builds; exported games need the matching `template_release` binaries present.
- Register classes at `MODULE_INITIALIZATION_LEVEL_SCENE`.
- gdext minimum is Godot 4.2 (4.1 support frozen).

## Skill-authoring implications

- **C# parity:** only the "Using from GDScript" section has a `gdscript` block → pair it with a C# usage block.
  All C++/Rust sections have no `gdscript` block → **no validator parity warning, no allowlist needed.**
- Keep core SKILL.md ≤ 16 KB: push Rust (gdext) + native debugging to `references/` (Pattern X).
- Cross-ref: `csharp-godot` (when native beats C#), `gdscript-advanced` (perf idioms), `godot-optimization`,
  `addon-development` (plugin distribution), `export-pipeline` (shipping the binaries).
