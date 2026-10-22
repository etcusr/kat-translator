# Kat Audit Lab — on-iPhone checks for the 22 Oct audit

**English** | [Русский](README.ru.md)

A separate Kat copy for checks O14–O17 and O19 of the [audit plan](../../../docs/maintenance/audit-fix-plan-2026-10-22.md). Name **Kat Audit Lab**, bundle `app.kattranslator.voicelab` (existing development profile valid until 2027-10-20; no new App ID is registered), its own data container. Kat (`app.kattranslator`) is never reinstalled, and its container is never read or written. The Live Activity extension is left out because its bundle has no profile.

## Space

| | iPhone | Mac |
|---|---:|---:|
| App | 0.21 GB | — |
| Index 9B + Index 2B + Irina/Lessac voices (copied from the Mac) | 7.23 GB | 0 (streamed from `model-store`) |
| Whisper Q8 downloaded inside the lab (this is check O16) | 0.87 GB | — |
| Headroom during the download (app space check: ×2 + 256 MB) | 2.0 GB | — |
| Lab build in `.build/audit-lab-2026-10-22` | — | 0.8 GB |
| **Free space needed before starting** | **≈ 10.5 GB, 12 GB recommended** | ≈ 1 GB |

Afterwards remove the copy with its container: `xcrun devicectl device uninstall app --device <id> app.kattranslator.voicelab`.

## Preparation (done)

`prepare.py --work .build/audit-lab-2026-10-22 --commit <commit>` builds a snapshot of committed code only. `build.sh <work>` runs a Release build and checks the bundle ID, that no extension is embedded, the signature and the increased-memory-limit entitlement.

## Installation (owner consent only)

`provision.py --device <UDID> --work .build/audit-lab-2026-10-22 --model-store model-store`:
- installs only the copy and refuses if one is already installed;
- copies the models with receipts into its container; the app checks SHA on first launch;
- compares the Kat app list before and after and checks that Kat is unchanged.

## Checks

**O16 downloads** (Whisper Q8, 0.87 GB):
1. Pause at ~30% and resume: expect it to continue, not restart.
2. Force-quit at ~50% and relaunch: expect resume data to be used.
3. Lock the phone until the download finishes in the background: expect a verified install, no second download and at most one `staging-*.bin`.

A full 9B background download (5.8 GB, ~12 GB more free space) only on a separate decision.

**O14 recording tail:**
- Five phrases with a distinct last word, pressing Stop right after it; count how often the last word is lost.
- If lost even once, change to `AudioQueueStop(queue, false)` with buffer draining and repeat.

**O15 camera recovery:** with the camera open, Settings → Developer → Reset Media Services; expect the preview to recover within ~5 s without closing the camera.

**O17 camera (C1–C4, O18):**
- Live overlay updates, with no ghost overlays after moving to other text or rotating.
- Photo overlay appears; Save puts it in Photos; Share gives a JPEG of about 1–3 MB.
- A history entry with the picture is created, also when the camera is closed right after the shot.
- C4: Start stays available after a translation preparation failure.
- No UI hangs.

**O19 memory on model switch:**
- Launch with `OT_MT_MEMORY_TRACE=1` through `devicectl process launch --environment-variables`.
- Run RU→EN on Index 9B, then switch to Index 2B and back with Whisper loaded; three cycles.
- Collect footprint, lifetime peak, available memory and memory warnings; decide M3 from this data.

Recordings, transcripts, logs and device identifiers stay outside Git; only aggregates are published. Never upload this lab to the Store or TestFlight.
