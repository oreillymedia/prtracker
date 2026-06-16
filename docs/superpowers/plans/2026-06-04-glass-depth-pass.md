# Liquid Glass Depth Pass — Implementation Plan

> **For agentic workers:** Implement task-by-task; each task builds + keeps tests green + is committed. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix the washed-out, no-separation look of the main window by (1) giving the source list a native `List(.sidebar)` so it gets the system sidebar material and selection, and (2) recessing the detail content plane so thread/activity cards read as elevated.

**Architecture:** Two independent changes. Task 1 swaps the custom `ScrollView`+`LazyVStack` source list for a native `List(selection:)` with `.listStyle(.sidebar)`, delegating selection/hover/keyboard-nav to the system and removing the hand-rolled equivalents in `MailRowView`. Task 2 sets a recessed background on the detail content so the (white) cards stand out, with a subtle shadow on the top-level cards.

**Tech Stack:** SwiftUI (macOS 26.4), SwiftData.

**Note on values:** The specific insets/colors/shadows below are sensible starting points. After implementation the human will visually verify and may ask to tune them — that's expected, not a failure.

**Verification per task:** `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` (BUILD SUCCEEDED) + `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` (all pass).

---

## Task 1: Native sidebar List

**Files:**
- Modify: `PRTracker/Views/Mail/MailListView.swift` (body + remove `moveSelection`)
- Modify: `PRTracker/Views/Mail/MailRowView.swift` (drop hand-rolled selection/hover/separator)

- [ ] **Step 1: Replace the MailListView body's list container with a `List(.sidebar)`**

Replace the `body` from the `VStack(spacing: 0) { ScrollView { ... } .focusable()...onKeyPress... }` block (lines 20–55) — i.e. everything between `let visible = ...` and the `.onAppear` modifier — with a `List`. The `.onAppear`, both `.onChange` handlers, and the `.toolbar` modifier stay attached, now to the `List`:

```swift
        List(selection: $appState.selectedPRID) {
            if visible.isEmpty {
                Text("Nothing in this filter.")
                    .font(.system(size: 12.5).italic())
                    .foregroundStyle(Tokens.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            } else {
                ForEach(visible) { pr in
                    MailRowView(pr: pr, isSelected: appState.selectedPRID == pr.id, viewerLogin: viewerLogin)
                        .tag(pr.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            if isResolved(pr) {
                                Button("Mark as unresolved") { markAsUnresolved(pr) }
                            } else {
                                Button("Mark as resolved") { markAsResolved(pr) }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
```

The `List` selection binding is `$appState.selectedPRID` (a `String?`), and each row is tagged with `pr.id` (a `String`) so native single-selection drives the existing `selectedPRID` state directly. The `.onAppear` / `.onChange(of: appState.selectedPRID)` / `.onChange(of: appState.activeFilter)` / `.toolbar` modifiers from the current code remain unchanged and attach to this `List`.

- [ ] **Step 2: Delete the now-dead `moveSelection` helper**

`List` provides arrow-key navigation natively, so the manual handler is dead. Delete the entire `// MARK: - Keyboard navigation` section and the `moveSelection(by:in:)` method (current lines 169–181).

- [ ] **Step 3: Strip hand-rolled selection/hover/separator from `MailRowView`**

The native sidebar `List` now draws selection highlight, hover, and row layout. In `PRTracker/Views/Mail/MailRowView.swift`:

(a) Remove the hover state and handler. Delete `@State private var hover = false` (line 8), the `.onHover { hover = $0 }` modifier (line 67), and the `rowBackground` computed property (lines 78–84).

(b) Remove the `.background(rowBackground)` modifier (line 64) and the bottom hairline `.overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .bottom)` (line 65) from the body. Keep `.contentShape(Rectangle())` and `.opacity(dimRow ? 0.55 : 1.0)`.

(c) In `topLine`, change the title color so it no longer overrides on selection — replace `.foregroundStyle(isSelected ? Tokens.accentText : Tokens.text)` (line 90) with `.foregroundStyle(Tokens.text)`. (The native selection highlight provides emphasis; forcing accent text fights it.)

Keep the `isSelected` parameter (still used by `dimRow`) and everything else (the `TodoRing`, lines, chips, padding) unchanged.

- [ ] **Step 4: Build** — `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` → BUILD SUCCEEDED.
- [ ] **Step 5: Test** — `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` → all pass.
- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/Mail/MailListView.swift PRTracker/Views/Mail/MailRowView.swift
git commit -m "feat(ui): native List(.sidebar) source list for glass material + selection"
```

---

## Task 2: Recess the detail plane so cards float

**Files:**
- Modify: `PRTracker/Views/Detail/PRDetailView.swift` (recessed content background)
- Modify: `PRTracker/Views/Detail/ThreadCard.swift` (card shadow)
- Modify: `PRTracker/Views/Detail/TimelineEventRow.swift` (card shadow)

- [ ] **Step 1: Recess the detail content background**

In `PRTracker/Views/Detail/PRDetailView.swift`, the detail content is `VStack(spacing: 0) { MailDetailHeader(...); ScrollView { ... } }`. Add a recessed background to that `VStack` so the white content cards stand out against it. Add `.background(Color(nsColor: .underPageBackgroundColor))` as the FIRST modifier on the `VStack` — i.e. immediately after the `VStack { ... }` closing brace and before `.navigationTitle(pr.title)`:

```swift
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationTitle(pr.title)
```

(The glass toolbar and inspector float above this; the recess only affects the scrolling content plane and the metadata subheader, which is intended.)

- [ ] **Step 2: Add a subtle elevation shadow to the top-level thread card**

In `PRTracker/Views/Detail/ThreadCard.swift`, find the card's surface modifier (around line 41): `.background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))` followed by its `.overlay(RoundedRectangle(cornerRadius: 10).stroke(...))`. Immediately AFTER that `.overlay(...)` stroke line, add:

```swift
        .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
```

(Add it to the outer card container only — the same view that has the `cornerRadius: 10` background. Do not add shadows to nested elements inside the card.)

- [ ] **Step 3: Add the same shadow to the timeline/activity card**

In `PRTracker/Views/Detail/TimelineEventRow.swift`, find the card surface (around line 86): `.background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))` and its following `.overlay(RoundedRectangle(cornerRadius: 8).stroke(...))`. Immediately AFTER that `.overlay(...)` stroke line, add:

```swift
        .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
```

- [ ] **Step 4: Build** — `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` → BUILD SUCCEEDED.
- [ ] **Step 5: Test** — `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` → all pass.
- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/Detail/PRDetailView.swift PRTracker/Views/Detail/ThreadCard.swift PRTracker/Views/Detail/TimelineEventRow.swift
git commit -m "feat(ui): recess detail content plane so cards read as elevated"
```

---

## Done

The sidebar now renders on the system sidebar material with native selection (clear separation from the detail), and the detail content sits on a recessed plane so the cards read as elevated surfaces — addressing the washed-out, no-separation appearance while staying within Liquid Glass (material/tone separation, not heavy borders). Visual tuning of the recess color / shadow / row insets is expected as a follow-up after the human reviews it live.
