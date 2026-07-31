# Launch Checklist — Wretched Blade

## 🚨 Pre-Release / Production Audit

- [ ] **Strip / Guard God Mode & Dev Cheats**:
  - `GameManager.gd`: Remove `is_god_mode` or wrap `toggle_god_mode()` in `OS.is_debug_build()` check so cheat commands cannot be triggered in production release builds.
- [ ] **Debug Logs**: Disable high-frequency `print()` / debug output across world gen and combat loops.
- [ ] **Performance Audit**: Verify 60 FPS target on mobile display targets.
