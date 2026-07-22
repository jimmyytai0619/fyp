em# Integration Notes — On-device AI Classification (Modules 2 & 3)

This documents the on-device Google ML Kit classification merged into the
existing **SmartMatch** project. It is **additive** and conforms to the project's
Provider architecture, `ApiService`, and `found_items` schema. It does not change
the server-side matching backend.

## Features implemented (mapped to the FYP report)

| Report ref | Feature | Where |
| --- | --- | --- |
| FR 2.1 | Capture / upload photo | `ReportItemViewModel.pickImage` (existing) |
| FR 2.2 | AI category classification | `ClassificationService.classify` → mapped to the 4 dropdown categories |
| FR 2.3 | Auto-generated description ("Black leather wallet") | `ClassificationService._buildDescription`; fills the Description field |
| FR 2.4 | Review / edit before saving | dropdown + editable Description (user can override everything) |
| FR 2.5 | Mandatory category, description, **date found**, location | Date Found field + validators in the View and `submitReport` |
| FR 2.6 | Visual attributes: colour, material, **brand/logo** | dominant-colour + material keyword + OCR text (`google_mlkit_text_recognition`) |
| Algorithm 4.7.1 | **Three-tier confidence** handling | see below |

### Three-tier confidence (Algorithm 4.7.1)

`ClassificationService` thresholds: `highThreshold = 0.75`, `mediumThreshold = 0.50`
(ML Kit's own `confidenceThreshold` is 0.50, so nothing below 0.50 is returned).

- **HIGH (≥ 75%)** → green card; category + description auto-filled; colour/brand
  added as tags.
- **MEDIUM (50–75%)** → blue card; the user taps one of the suggested category
  chips, which then fills the form.
- **LOW (< 50% / nothing recognised)** → orange "Item not recognized" card; the
  user must choose the category and type a description manually.

## Files changed / added

| File | Change |
| --- | --- |
| `pubspec.yaml` | added `google_mlkit_image_labeling`, `google_mlkit_commons`, `palette_generator`, `google_mlkit_text_recognition` |
| `lib/services/classification_service.dart` | ML Kit labeling + OCR + dominant colour; tiers, multi-suggestions, description generator, material inference, brand detection |
| `lib/viewmodels/report_item_viewmodel.dart` | runs classification on `pickImage`; exposes tier/suggestions/description/brand; validates FR 2.5; threads found-date |
| `lib/views/report_item/report_item_view.dart` | tier-aware AI card, suggestion chips, brand/colour/material chips, Date Found picker, required-field validation |

**No changes** to `ApiService`, the database, or the matching backend.

### Date Found persistence

To avoid a DB migration, the found-date is appended to the saved description
(e.g. `"… (Found on: 2026-06-29)"`). To make it a first-class column, add a
nullable `date_found` column to `found_items` and pass `dateFound` through
`ApiService.reportFoundItem` instead.

## ⚠️ Report vs. code discrepancy to resolve before the viva

The FYP report's Chapter 4 describes **Firebase** (Firestore, Firebase Auth,
Firebase Storage, gRPC, Firestore Security Rules). The actual implemented app
uses **Supabase** (Postgres + Supabase Auth + Supabase Storage) plus a **Python
FastAPI** matching backend. Either update the report's architecture/design
chapters to Supabase, or explicitly note the platform change. An examiner will
likely flag this.

The report also commits to measurable NFRs you'll need to evidence in Chapter 5:
classification < 3 s (NFR 1.1), ≥ 80% accuracy (NFR 3.1), ≤ 4 interactions
(NFR 2.1). Plan a small labelled-image evaluation to back these up.

## Platform setup

1. `flutter pub get` (if ML Kit pins don't resolve: `flutter pub add
   google_mlkit_image_labeling google_mlkit_commons google_mlkit_text_recognition`).
2. **Android**: `minSdkVersion 21+` (Flutter default is fine). Camera/gallery
   permissions already handled by the existing `image_picker` setup.
3. **iOS**: deployment target **15.5+** in `ios/Podfile`, exclude `armv7`
   (ML Kit is 64-bit only), and ensure `NSCameraUsageDescription` is in
   `Info.plist`.

> ML Kit is Android/iOS only — no web/desktop, which is fine for SmartMatch.

## Tuning

Edit `ClassificationService`: `highThreshold` / `mediumThreshold` for the tiers,
and the keyword lists in `_mapToCategory` / `_inferMaterial` as you observe real
on-device labels.
