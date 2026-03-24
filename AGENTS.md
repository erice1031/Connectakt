# AGENTS.md — Connectakt

> **For AI coding agents (Claude, Codex, etc.):** Read this file first before touching any code.

---

## Read these files first (required)

Before writing any code, read these files **in order**:

1. **`CLAUDE.md`** — Architecture, key files, known constraints, Digitakt hardware specs
2. **`CODEX.md`** — Current task list with step-by-step implementation guides
3. **`tasks/lessons.md`** — Mistakes made in prior sessions — read every entry
4. **`tasks/todo.md`** — Current task progress and acceptance criteria
5. **`WORKFLOW_ORCHESTRATION.md`** — Workflow rules for how to collaborate

Do not skip this step. The lessons file in particular will save you from repeating hard-won mistakes.

---

## Build & verify

Always build before marking any task complete:

```bash
# Build for iOS simulator
xcodebuild -workspace Connectakt.xcworkspace -scheme Connectakt -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run unit tests
xcodebuild -workspace Connectakt.xcworkspace -scheme ConnektaktTests -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

**Zero errors required.** Warnings are acceptable but document new ones in `tasks/lessons.md`.

Build one target at a time. Do NOT run multiple xcodebuild commands in parallel — they share derived data and will conflict.

---

## Starting work

- Default to **Task 1** in `CODEX.md` unless told otherwise by the user.
- Complete one task fully (all acceptance criteria checked) before starting the next.
- Read the referenced source files in each task before writing any code — signatures change.
- If a task depends on a previous task being complete, check CODEX.md for the commit hash.

---

## Keeping records (required)

After completing a task or receiving a correction, update these files:

### 1. Update `CODEX.md`
Mark the task complete:
```
## Task N — Description [✅ DONE]

> Completed: YYYY-MM-DD
> Commit: <hash>
> Notes: <anything the next developer needs to know>
```

### 2. Update `CLAUDE.md`
- Add new key files to the architecture reference table
- Update known bugs / constraints section
- Update any API signatures that changed

### 3. Update `ROADMAP.md`
- Move completed phase items from "Next Up" to "✅ Completed" with commit hash
- Update "Last updated" date

### 4. Update `tasks/todo.md`
- Check off completed items
- Add new items as discovered
- Keep the "In Progress" section current

### 5. Update `tasks/lessons.md`
- After ANY user correction: add a lesson entry immediately
- Format: `## <Pattern Name> (YYYY-MM-DD)` followed by one paragraph

---

## What not to do

- Do NOT commit `.env` files, secrets, or API keys
- Do NOT run `git push` — the user handles all remote pushes
- Do NOT modify `AGENTS.md` itself (except to add critical constraints at the bottom)
- Do NOT use deprecated AVFoundation APIs (check iOS 17+ docs)
- Do NOT assume the Digitakt uses standard MTP — it has a custom Elektron Transfer protocol
- Do NOT write code that requires macOS-only frameworks in the shared iOS target
- Do NOT use `AVAudioUnitDynamicsProcessor` — it is iOS-only and will not compile on macOS targets

---

## Critical Constraints

### Hardware Reality
- Digitakt uses **USB-B port** (standard USB, not USB-C)
- iPhone connection requires USB-B → USB-C adapter (or Lightning for older iPhones)
- Digitakt communicates via **Elektron Transfer protocol** over USB (not standard MTP)
- Digitakt is a **USB audio class device** — it can act as a USB audio interface
- Sample format MUST be: **WAV, 16-bit, 44.1kHz or 48kHz, mono preferred**

### iOS/iPadOS Specifics
- USB device discovery uses `ExternalAccessory` framework (requires MFi) OR `CoreUSB` (iOS 16+)
- USB audio recording requires `AVCaptureSession` with USB audio source
- AUV3 requires separate app extension target with proper entitlements
- iCloud requires `com.apple.developer.icloud-container-identifiers` entitlement

### Monetization
- Base price: $7.99 USD
- Introductory offer: 60% off (~$3.19) for first month
- Free tier: browse + single sample transfer
- Pro tier: full editor, AUV3 host, batch operations, recording mode
