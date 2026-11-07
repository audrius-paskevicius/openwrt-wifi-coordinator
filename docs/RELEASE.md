# 0.6.0-r7

Initial public source release of the combined OpenWrt Wi-Fi Coordinator and Radio Preference package.

- Coordinated channel and width planning, paced surveys, DFS preparation, and decaying radar memory.
- Per-candidate comparison evidence survives changing winners.
- Shared automatic policy: try compatible handoff, then switch with brief client reconnection if needed; verify and recover service afterward.
- LuCI channel, client, and history pages with bundled Chart.js.
- RAM buffering, six-hour flash batches, configurable retention up to 200 hours, and orderly-shutdown checkpoints.
- Source, build scripts, isolated tests, documentation, license notices, signed APK, public key, and checksums included.

Validated on WRT3200ACM / OpenWrt 25.12.6. The targeted occupied-radio test reconnected its client after roughly ten seconds. This is an experimental third-party package; other hardware and a complete firmware-upgrade cycle remain unvalidated. See the README before installing: Automatic mode and the reconnect fallback are enabled by default.

The published APK is the same signed 0.6.0-r7 build validated on the development router. Public-project changes add portable tooling, documentation, line-ending normalization, and configurable build inputs; they do not change the packaged runtime behavior.
