---
title: Footgun — SQLite Cache File Default Permissions
type: note
permalink: gittickets/footguns/footgun-sq-lite-cache-file-default-permissions
tags:
- footgun
- security
- storage
- macos
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

`sqlite3_open_v2(...CREATE...)` creates the database file with the process's current umask (typically 0644 on macOS), leaving it world-readable. On a non-sandboxed macOS host (CLI tools, developer apps, anything not in the App Sandbox), any second OS user with shell access can:

```
sqlite3 ~user/Library/Application\ Support/.../submissions.sqlite \
  "SELECT body, title, device_id FROM submissions"
```

…and read every bug body the user has ever filed, including any pre-redaction text the developer enabled. iOS is unaffected (sandbox isolates the file per app), but the SDK ships on both platforms.

Discovered in code review of PR 4.

## Observations

- [rule] After opening a SQLite database, immediately `FileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath:)`. See `SubmissionCache.restrictPermissions(at:)` for the reference impl. #security
- [rule] Apply the same chmod to the WAL (`-wal`) and SHM (`-shm`) sibling files when SQLite creates them. WAL mode is off in our default but a future change could flip it; the chmod is defensive. #security
- [rule] Failures from `setAttributes` are not fatal (the cache itself works either way) but should be best-effort silent — log via `GitTicketsLogger` if logging is wired. We currently `try?` and proceed. #security
- [rule] When choosing a default file location, prefer Application Support over `/tmp` or `/var` even though Application Support is per-user; the host's bundle identifier scopes it. Same default applies on iOS (sandboxed) and macOS (non-sandboxed) — but only on macOS does the chmod matter. #storage
- [related] Same lesson applies to ANY file the SDK creates (export bundles, screenshot temp files, log files). Default to 0600 unless there's a reason to be wider.
- [related] [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]] — sibling "platform default isn't what you want" lesson, different storage layer.

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
- prevents_recurrence_of "submission cache world-readable on multi-user macOS"
