# Implementation Plan - Remember Me Feature

This plan outlines the changes required to add a "Remember Me" checkbox to the login page. When checked, the application will persist the user's email and automatically populate it the next time the login page is opened.

## User Review Required

> [!NOTE]
> This implementation will persist the **email only** for security reasons. Persisting passwords in plain text is not recommended.

## Proposed Changes

### Dependencies

#### [pubspec.yaml](file:///C:/RSW/FYP/fyp/pubspec.yaml)
- Added `shared_preferences` for local storage of the remembered email. (Already done via shell command).

### ViewModels

#### [auth_viewmodel.dart](file:///C:/RSW/FYP/fyp/lib/viewmodels/auth_viewmodel.dart)
- Update the `login` method to accept a `rememberMe` boolean.
- Add logic to save or clear the email in `shared_preferences` based on the `rememberMe` flag.
- Add a method `getRememberedEmail()` to retrieve the saved email on initialization.

### Views

#### [login_view.dart](file:///C:/RSW/FYP/fyp/lib/views/auth/login_view.dart)
- Add a `bool _rememberMe = false` state variable.
- Add a `CheckboxListTile` or a custom `Row` with a `Checkbox` and "Remember Me" label below the password field.
- In `initState`, call `authViewModel.getRememberedEmail()` and populate `_emailCtrl` if an email is found.
- Pass the `_rememberMe` value to the `login` method in `_submit`.

## Verification Plan

### Manual Verification
1. **Open Login Page**: Verify the "Remember Me" checkbox is visible.
2. **Login with Remember Me Checked**:
   - Enter email and password.
   - Check "Remember Me".
   - Click "Login".
   - Logout or restart the app.
   - Verify that the email field is pre-filled.
3. **Login with Remember Me Unchecked**:
   - Enter a different email.
   - Ensure "Remember Me" is unchecked.
   - Click "Login".
   - Logout or restart the app.
   - Verify that the email field is empty (or cleared if it was previously saved).
4. **Security Check**: Verify that the password field is **never** pre-filled.
