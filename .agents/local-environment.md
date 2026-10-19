# Local Environment

This note records workstation-specific facts observed on 2026-10-20. They are useful for local development and app
troubleshooting; repository-wide version requirements remain in `project.md` and `commands.md`.

## Checkout and Host

- The Git checkout is `/Users/snowson/workspace/code/ficlash-statistics/flclash`. Its parent is a workspace folder, not
  the repository root; it may contain local release artifacts such as `FlClash-0.8.99-macos-arm64-stats7.dmg`.
- The host is macOS 27.0.1 on Apple Silicon (`arm64`). The installed app is `/Applications/FlClash.app`, version 0.8.99.

## Flutter Toolchain

- `flutter` is not on the agent shell's `PATH`. The SDK executable exists at `/Users/snowson/sdk/flutter/bin/flutter`.
- In the managed shell, invoking that executable attempted to refresh files under the SDK cache and was denied by the
  filesystem sandbox. Use an execution environment that can write its SDK cache before running Flutter commands.
- The release SDK pin is documented in `project.md`; do not infer it from the installed SDK path alone.

## Installed FlClash Data

- The installed app keeps per-user data under `~/Library/Application Support/com.follow.clash/`. Its generated
  `config.yaml` and `scripts/` directory are local runtime state, not repository configuration.
- The currently observed override script is
  `~/Library/Application Support/com.follow.clash/scripts/353341717266567168.js`. The script header says it is applied
  when the subscription is updated; editing the file alone does not prove the generated config or running Core has
  reloaded it.
- Keep machine-specific profile data and credentials out of this repository. Follow the safe-mode and process-ownership
  rules in `rules.md` before launching or stopping FlClash on the host.
