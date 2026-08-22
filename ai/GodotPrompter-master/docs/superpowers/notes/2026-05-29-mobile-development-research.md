# Mobile Development — Godot 4.x Research Digest (for the `mobile-development` skill)

> Gathered 2026-05-29 from the LOCAL official Godot docs clone at `D:\Godot\godot-docs`
> (read directly from disk; spot-claims cross-checked). Sources cited per section.
> Godot 4.x, GDScript + C#, repo minimum 4.3+.

## 1. Export & signing (deltas from generic export)

**Android** (`tutorials/export/exporting_for_android.rst`):
- **OpenJDK 17** required. Android SDK via Android Studio or `sdkmanager`. Set `Java SDK Path` +
  `Android SDK Path` in **Editor Settings** (per-user, not per-project).
- Release signing: generate keystore via
  `keytool -v -genkey -keystore mygame.keystore -alias mygame -keyalg RSA -validity 10000`;
  preset fields **Release / Release User / Release Password** (keystore pw and key pw must currently match).
  Uncheck **Export With Debug**.
- **AAB** mandatory for new Play uploads (since Aug 2021). APK bundles ARMv7+ARMv8 by default.
- Launcher icons: Main (≥192²), Adaptive (Android 8+, ≥432²), Themed (Android 13+).
- CI env-var overrides: `GODOT_ANDROID_KEYSTORE_{DEBUG,RELEASE}_{PATH,USER,PASSWORD}`,
  `GODOT_SCRIPT_ENCRYPTION_KEY`.

**Custom Gradle build** (`tutorials/export/android_gradle_build.rst`):
- Installs an Android Java project into `res://android/build`, compiled as the export template each export.
- **Required for v2 plugins and IAP.** Install via **Project → Install the Gradle Build template**; enable
  per-preset (`gradle_build/use_gradle_build`).

**iOS** (`tutorials/export/exporting_for_ios.rst`):
- **macOS + Xcode** required. Export needs **App Store Team ID** (10-char) + bundle **Identifier**
  (reverse-DNS). Godot **generates an `.xcodeproj`** — build/deploy/release from Xcode.
- **iOS simulator supports the `Compatibility` renderer only.**
- Env overrides: `GODOT_IOS_PROVISIONING_PROFILE_UUID_{DEBUG,RELEASE}`.

## 2. App lifecycle (`class_node.rst` + `tutorials/inputs/handling_quit_requests.rst`)

Verbatim `Node` notification constants (+ values):
- `NOTIFICATION_WM_GO_BACK_REQUEST` = 1007 (Android Back button)
- `NOTIFICATION_APPLICATION_RESUMED` = 2014
- `NOTIFICATION_APPLICATION_PAUSED` = 2015 (suspended to background)
- `NOTIFICATION_APPLICATION_FOCUS_IN` = 2016 / `..._FOCUS_OUT` = 2017
- **No `NOTIFICATION_WM_CLOSE_REQUEST` on mobile** (desktop/web only).

Handling: autosave/cleanup on `APPLICATION_PAUSED`. **iOS gives ~5 s** after pause to finish work or it
kills the app. Android Back exits if **Application > Config > Quit On Go Back** is on (default) and fires
`WM_GO_BACK_REQUEST`. C#: `_Notification(int what)` override; docs only show `NotificationWMCloseRequest`
verbatim — the paused/resumed/focus PascalCase names follow the pattern but **aren't shown** (author + verify).

## 3. Permissions (`class_os.rst`, `class_editorexportplatformandroid.rst`, `class_mainloop.rst`)

- Declared in the Android export preset as `permissions/<name>` booleans (e.g. `permissions/camera`).
- Runtime: `OS.request_permission(name) -> bool` (e.g. `"android.permission.POST_NOTIFICATIONS"`),
  `OS.request_permissions() -> bool` (all dangerous; Android-only), `OS.get_granted_permissions()
  -> PackedStringArray`, `OS.revoke_granted_permissions()`.
- **Permission must ALSO be enabled in the export preset**, not just requested at runtime.
- Result signal: `MainLoop.on_request_permissions_result(permission: String, granted: bool)`.
- Docs give the API but **no tutorial request→result example** — author it ourselves.

## 4. Plugins

**Android v2** (`platform/android/android_plugin.rst`, `android_library.rst`) — **Godot 4.2+** (v1 deprecated 4.2):
- A v2 plugin = an Android library (AAR) depending on `org.godotengine:godot:<version>` (MavenCentral),
  init class extends `GodotPlugin`. **Requires Gradle build + Godot 4.2+.**
- Expose methods to GDScript with `@UsedByGodot` (name must match EXACTLY — no case coercion). Access:
  ```gdscript
  if Engine.has_singleton("MyPlugin"):
      var s = Engine.get_singleton("MyPlugin")
      print(s.myPluginFunction("World"))
  ```
- Packaging uses the standard `EditorExportPlugin` format (`@tool extends EditorPlugin` + `plugin.cfg`),
  implementing `_get_android_libraries`, `_get_android_dependencies`, manifest-contents hooks, etc.
- GDExtension Android plugin: `plugin.gdextension` with `android_aar_plugin = true`.
- Templates: `m4gr3d/Godot-Android-Plugin-Template`, `m4gr3d/GDExtension-Android-Plugin-Template`.

**JavaClassWrapper + AndroidRuntime** (`platform/android/javaclasswrapper_and_androidruntimeplugin.rst`)
— **Godot 4.4+ (NOT 4.3).** The single biggest version gate; label examples "Godot 4.4+".
- `JavaClassWrapper` singleton: call Java/Kotlin classes from GDScript/C#/GDExtension with **no plugin**:
  ```gdscript
  var LocalDateTime = JavaClassWrapper.wrap("java.time.LocalDateTime")
  var datetime = LocalDateTime.now()
  ```
- `AndroidRuntime` singleton (`Engine.get_singleton("AndroidRuntime")`): `getActivity()`,
  `getApplicationContext()`, `createRunnableFromGodotCallable(callable)`.
- Documented recipes: Toast, vibrate via `VibrationEffect`, inner classes via `$`
  (`"android.os.Build$VERSION"`), constructors (call method same name as class), Intents.
- Gradle exports auto-include `.jar`/`.aar` dropped in the project `addons` dir → usable via JavaClassWrapper.

**iOS plugins** (`platform/ios/ios_plugin.rst`, flagged outdated):
- `.a`/`.xcframework` + `.gdip` INI in `res://ios/plugins/`; access via `Engine.get_singleton("MyPlugin")`.
- `.gdip`: `[config]` (name, binary, initialization, deinitialization), `[dependencies]` (linked/embedded/
  system/capabilities/files/linker_flags), `[plist]`.
- Templates: `godotengine/godot-ios-plugins`, `naithar/godot_ios_plugin`.

## 5. In-app purchases (`platform/android/android_in_app_purchases.rst`)

- First-party **`GodotGooglePlayBilling`** plugin — **Godot 4.2+, requires Gradle build.** (GDScript-only docs.)
- `BillingClient`: `new()` → connect signals → `start_connection()`; `is_ready()`, `get_connection_state()`
  (`ConnectionState{DISCONNECTED,CONNECTING,CONNECTED,CLOSED}`).
- Signals: `connected`, `disconnected`, `connect_error(code, msg)`, `query_product_details_response(resp)`,
  `query_purchases_response(resp)`, `on_purchase_updated(resp)`, `consume_purchase_response`,
  `acknowledge_purchase_response`.
- Methods: `query_product_details(ids, type)`, `query_purchases(type)`, `purchase(product_id)`,
  `purchase_subscription(...)`, `consume_purchase(token)`, `acknowledge_purchase(token)`.
- Types: `ProductType.INAPP/.SUBS`, `BillingResponseCode.OK`, `PurchaseState{UNSPECIFIED,PURCHASED,PENDING}`.
- Rules: query details before purchase; acknowledge one-time purchases within 3 days or auto-refund;
  `consume_purchase` auto-acknowledges; never award `PENDING`.
- **iOS IAP: no documented first-party API** — only mentioned as an iOS-plugin use case.

## 6. Device features & safe area (`class_displayserver.rst`, `class_input.rst`)

- `DisplayServer.get_display_safe_area() -> Rect2i` — **Android + iOS only** (else `screen_get_usable_rect`).
- `DisplayServer.get_display_cutouts() -> Array[Rect2]` — **Android only**.
- Sensors on `Input` (`Vector3`, Android+iOS only, else `Vector3.ZERO`): `get_accelerometer()`,
  `get_gravity()`, `get_gyroscope()`, `get_magnetometer()`.
- `Input.vibrate_handheld(duration_ms := 500, amplitude := -1.0)` — **needs `VIBRATE` permission** in the
  preset on Android or it's a no-op; iOS duration needs iOS 13+.

## 7. Performance / renderer

- iOS simulator = `Compatibility` renderer only. Use Mobile/Compatibility for mobile targets.
- Texture compression: set `rendering/textures/vram_compression/import_etc2_astc = true` (ETC2/ASTC) for
  Android (verbatim recommendation in `android_library.rst`).
- File size: single-arch APKs, size-optimized templates; AABs split per-device automatically.
- **No dedicated mobile perf-tuning section in these pages** — cross-ref `godot-optimization`.

## 8. Crash debugging (`platform/android/resolving_crashes_on_android.rst`)

- Need **native debug symbols** matching the build. Official templates ship per-release symbol zips.
- Custom builds: add `debug_symbols=yes separate_debug_symbols=yes` to SCons (last arch only).
- Upload to Play Console (Native debug symbols), or symbolicate locally with NDK `ndk-stack -sym <dir> -dump crash.txt`.
- Live debugging: `adb logcat`.

## 9. C# on mobile (`c_sharp/index.rst`, `c_sharp_basics.rst`, export pages)

- C# Android **and** iOS export — **Godot 4.2+ but EXPERIMENTAL** (verbatim `.. attention::`).
- **Godot 4.5 requires .NET 8+, but exporting to Android requires .NET 9+** (verbatim).
- iOS simulator C# templates: **x64 only**; iOS export only from macOS.
- **C# cannot export to Web.** No detailed NativeAOT-on-mobile guidance in these pages.

## Doc-coverage flags

**Version gates (be precise — repo targets 4.3+):**
- `JavaClassWrapper` / `AndroidRuntime` → **4.4+** (label clearly; not in 4.3).
- Android v2 plugins + Gradle plugins → **4.2+**.
- `GodotGooglePlayBilling` → **4.2+** + Gradle.
- C# Android/iOS export → **4.2+** experimental; Android C# needs **.NET 9+** (Godot 4.5).
- Everything else (lifecycle, permissions, safe area, sensors, vibrate) is fine on 4.3.

**GDScript-only in docs (author C# parity ourselves):** JavaClassWrapper/AndroidRuntime examples,
GodotGooglePlayBilling IAP, the v2-plugin `@tool` export script, and the lifecycle paused/resumed/focus
C# constant names (only `NotificationWMCloseRequest` shown verbatim).

**Not covered (write from scratch / cross-ref):** mobile perf tuning (→ `godot-optimization`), safe-area
*application* recipe (→ `responsive-ui`), iOS IAP concrete API, touch input (→ `input-handling`), C# AOT
specifics, the permission request→result loop.

**Related-skills line targets:** `export-pipeline`, `responsive-ui`, `input-handling`,
`godot-optimization`, `csharp-godot`.
