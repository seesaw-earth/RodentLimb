---
outline: false
---

# Accessibility

RodentLimb is built with Apple's standard controls (SwiftUI and native macOS tables), so it follows system appearance settings such as Dark Mode, Increase Contrast and Reduce Transparency where macOS applies them to standard controls.

## On the Mac

- **Keyboard first.** Every main command has a menu item and most have a shortcut, including importing, tracking, QC review (**I** include, **E** exclude, ↑ / ↓ next video), relabeling events (1–9, 0) and frame-by-frame playback. See [Keyboard shortcuts](./guide/shortcuts.md).
- **VoiceOver.** Menus, tables, buttons, sliders and text fields use standard controls that VoiceOver reads. Video frames, keypoint overlays and charts are visual; every number shown in a chart is also in the measures table and the exported CSV files.
- **Color is not the only cue.** Event labels and QC verdicts are written as text, not shown by color alone.
- **Language.** English or Simplified Chinese, switchable in the app.

## This website

This manual is a static site with semantic headings, a search box, a visible language switch, light and dark themes, and a layout that works on phones. Tables carry the same information as the figures they accompany.

## Known limits

- Reviewing pose quality and behavior events relies on watching the video. If you cannot review video, ask a colleague to confirm a sample of events.
- Some charts do not yet have full VoiceOver descriptions; use the measures table or the exports instead.

## Feedback

If something in the app or on this site is hard to use with your setup, please tell us in an issue at [github.com/seesaw-earth/RodentLimb/issues](https://github.com/seesaw-earth/RodentLimb/issues), and mention the assistive technology you use.
