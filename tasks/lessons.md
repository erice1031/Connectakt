# Lessons Learned — Connectakt

## Elektron Transfer Protocol is NOT standard MTP (2026-03-23)
The Digitakt does not use standard Media Transfer Protocol (MTP) or Mass Storage Class (MSC) over USB. It uses Elektron's proprietary Transfer protocol. Do not assume standard USB file system access will work. Research the Elektron Transfer open-source implementation (elektron-ctl, pyelectron) before implementing any USB communication. The official Elektron Transfer desktop app is the reference implementation.

## Digitakt sample format is strict (2026-03-23)
Digitakt requires WAV files: 16-bit PCM, 44.1kHz or 48kHz, mono preferred (stereo supported but wastes RAM). Any deviation will either fail to import or cause playback artifacts. The optimizer MUST enforce these constraints — do not allow the user to bypass format conversion.

## USB audio from Digitakt requires USB Audio Class 2.0 (2026-03-23)
The Digitakt presents itself as a USB Audio Class 2.0 device when used as an audio interface. iOS requires the device to be USB Audio Class 2.0 compliant. Recording via AVCaptureSession should work, but test on real hardware — simulators cannot test USB audio.

## xcodebuild targets must be run sequentially (2026-03-23)
Never run multiple xcodebuild commands in parallel. They share derived data directories and will conflict, causing spurious build errors. Always run one target, wait for completion, then run the next.

## AUV3 offline preview must not await buffer scheduling (2026-03-29)
When using `AVAudioPlayerNode` with an offline `AVAudioEngine` render path, do not switch blindly to the newer async `scheduleBuffer` overload. In the editor's AUV3 preview chain this caused playback to stall before rendering started. Use immediate scheduling in the offline path, then validate on-device with a real AU before treating preview/freeze as stable.

## iOS AUV3 hosts need iOS-specific entitlements, not the macOS sandbox file (2026-03-31)
If third-party Audio Units are missing on-device while Apple built-in units still appear, do not keep expanding picker or registry diagnostics first. Check the signed iPhone app entitlements. Connectakt was using the macOS entitlement file for both platforms, which stripped down to a minimal iOS signing set and left the host without the `inter-app-audio` entitlement that Apple's own Audio Unit app template still includes for the containing iOS app. Split iOS and macOS entitlements so the phone build carries `inter-app-audio`, then retest discovery on real hardware.

## Regenerating the Xcode project can silently drop local source files from the build graph (2026-03-31)
If `xcodegen generate` is run while local source files are temporarily moved out of the tree, the regenerated `project.pbxproj` will stop including them and later builds can fail with missing-type errors even though the Swift files still exist on disk. This happened with `MusicalGrid.swift` and related recorder files. After regenerating, always confirm that newly referenced local files are still part of the target graph before trusting the next build result.
