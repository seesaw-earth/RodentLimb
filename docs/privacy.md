---
outline: false
---

# Privacy policy

*Last updated: November 2026 · applies to RodentLimb for Mac, iPhone and iPad*

**In short: RodentLimb does not collect, transmit or share any data. Everything you do in the app stays on your Mac or device.**

## What the app processes

RodentLimb processes, **on your Mac or device only**:

- videos you choose for analysis;
- the study details you enter, such as animal IDs, groups, sex, timepoints and notes;
- the keypoints, quality checks, results, charts and files the app computes from them;
- your settings, such as the interface language.

## What the app does not do

- It has **no network functions**. It does not upload, sync or send anything to the developer or to any server. The Mac app does not request network access at all.
- It has **no account**, sign-in or registration.
- It contains **no analytics, advertising, crash-reporting or tracking** code, and no third-party SDKs.
- It does **not** access your contacts, location, microphone or health data.

## You can check this

RodentLimb is open source; its source code is public at [github.com/seesaw-earth/RodentLimb](https://github.com/seesaw-earth/RodentLimb). The privacy manifest included in the app (`PrivacyInfo.xcprivacy`) declares no tracking and no collected data. The Mac app runs in the macOS App Sandbox.

## On the Mac

- **Files and folders.** The Mac app can read only the videos and folders you choose in an Open panel or drag into its window, and the library folder you choose. It keeps access to them with security-scoped bookmarks, so videos can stay where they are.
- **Where data are stored.** In the library: by default inside the app's container (`Documents/RodentLimb`), or in a folder you choose. Backups and Recently Deleted items are kept inside the library.
- **Library lock.** While a library is open, the file `.rodentlimb-lock.json` in it records the Mac's name and your macOS user name, so that a second Mac opening the same library (for example on a shared drive) can warn you. It is never sent anywhere; it is visible to whoever can open that folder.
- **Notifications.** If you allow notifications, macOS shows one when a batch finishes. The notification is created on your Mac.

## On iPhone and iPad

- **Photos.** Videos are chosen with the system photo picker. RodentLimb receives only the videos you select and has no access to the rest of your library.
- **Files.** Files you pick in the Files picker are read only when you pick them. The app copies the video into its own folder, *Files › On My iPhone › RodentLimb*.

## Backups and sharing

Your data are included in your Mac or device backups (Time Machine, iCloud or a computer) according to your own backup settings, which Apple governs. If you keep a library on a shared or cloud drive, that service's terms apply. Data leave your Mac or device only when **you** export or share them, and then only to the destination you choose.

## Deleting your data

Delete videos, analyses or studies in the app (on the Mac they go to Recently Deleted for 30 days, where you can also delete them at once), delete the library folder, or delete the app to remove the data in its container.

## This website

This manual is hosted on GitHub Pages. GitHub may log visitors' IP addresses for security; see the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). The site sets no cookies and uses no analytics of its own.

## Children

RodentLimb is a tool for research laboratories. It does not collect data from anyone, including children.

## Changes

If this policy changes, the new version will be posted on this page with a new date. A change that introduced any data collection would be stated clearly here and in the release notes before it took effect.

## Contact

Questions about this policy: open an issue at [github.com/seesaw-earth/RodentLimb/issues](https://github.com/seesaw-earth/RodentLimb/issues), or see [Support](./support.md).

Developer: Ziqing Shi
