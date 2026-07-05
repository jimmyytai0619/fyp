# Implementation Plan - Persistent Auto-Login

This plan outlines the changes required to transition the "Remember Me" feature from just remembering the email to a full persistent login (Auto-Login). If the user checks "Remember Me", they will be automatically directed to the Dashboard upon app restart.

## User Review Required

> [!IMPORTANT]
> This will use Supabase's built-in session persistence. If the user logs out, they will always return to the Login screen.

## Proposed Changes

### main.dart

#### [main.dart](file:///C:/RSW/FYP/fyp/lib/main.dart)
- Update `SmartMatchApp` to determine the initial route based on whether a valid Supabase session exists.
- In `build`, set `home` to either `DashboardView` (if logged in) or `LoginView` (if not).

### AuthViewModel

#### [auth_viewmodel.dart](file:///C:/RSW/FYP/fyp/lib/viewmodels/auth_viewmodel.dart)
- We will keep the `rememberMe` flag during login to satisfy the user's intent.
- Supabase handles session persistence automatically, but we can use the `rememberMe` flag to decide whether to *persist* that session or not (though standard practice in Supabase is to always persist, we can manually sign out if `rememberMe` was false on next launch, or more simply, just follow the user's request to "Direct login to main page").

### LoginView

#### [login_view.dart](file:///C:/RSW/FYP/fyp/lib/views/auth/login_view.dart)
- Keep the "Remember Me" checkbox as the toggle for this behavior.

## Verification Plan

### Manual Verification
1. **Login with Remember Me Checked**:
   - Log in.
   - Close the app (kill process).
   - Reopen the app.
   - Verify it goes directly to the **Dashboard**.
2. **Login with Remember Me Unchecked**:
   - Log in.
   - Close the app.
   - Reopen the app.
   - Verify it goes to the **Login Screen**.
3. **Logout Check**:
   - Log out from the Dashboard.
   - Verify it returns to the **Login Screen**.
   - Close and reopen.
   - Verify it stays on the **Login Screen**.
