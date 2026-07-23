# Implementation Plan - Dashboard Redesign

This plan outlines the changes to rearrange the home page (Dashboard) into a more intuitive layout with two primary categories and secondary rectangular actions.

## Proposed Changes

### Dashboard View

#### [dashboard_view.dart](file:///C:/RSW/FYP/fyp/lib/views/dashboard/dashboard_view.dart)

- **Restructure `_HomeTab`**:
    - Remove the `SliverGrid` layout for all actions.
    - Create a **"Main Actions"** section with two large, full-width cards:
        1. **"I Found Something"**: Directs to `ReportItemView` (Found).
        2. **"I Lost Something"**: A container containing two sub-actions: "Find My Lost Item" (Visual Search) and "Report Lost Item" (Manual Form).
    - Create a **"Secondary Actions"** section with rectangular cards (full-width or wider aspect ratio) for:
        - Manage My Records
        - My Claims
        - Browse Found Items
- **Update `_ActionCardWidget`**:
    - Update the styling to support the new rectangular and large category formats.
    - Ensure labels and descriptions are well-aligned for the new dimensions.

## Verification Plan

### Manual Verification
1. **Layout Check**:
   - Verify that "Report Found Item" is a large, prominent section.
   - Verify that "Find My Lost Item" and "Report Lost Item" are grouped under a "Lost" category.
   - Verify that "Manage", "Claims", and "Browse" are now rectangular instead of square.
2. **Navigation Check**:
   - Ensure all buttons still navigate to their correct respective screens.
3. **Responsiveness**:
   - Check the layout on the emulator to ensure padding and spacing look balanced.
