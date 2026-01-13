# User Profile Modal

A professional user profile management modal for the Golf Force Plate app.

## Features

- ✅ Clean, modern UI matching the Pro Tech Golf theme
- ✅ Form validation with helpful error messages
- ✅ Firebase Firestore integration for data persistence
- ✅ Loading and saving states with progress indicators
- ✅ Profile fields:
  - Username (required, min 3 characters)
  - Email (read-only, from Firebase Auth)
  - Phone Number (optional)
  - Golf Handicap (optional)
  - Experience Level (dropdown: Beginner, Intermediate, Advanced, Professional)

## Usage

### From Profile Screen

The modal is already integrated into the Profile Screen. Click the "Edit Profile" button to open it.

### From Any Other Screen

```dart
import 'package:golf_force_plate/widgets/user_profile_modal.dart';

// Show the modal
final result = await showDialog<bool>(
  context: context,
  builder: (context) => const UserProfileModal(),
);

// Check if profile was updated
if (result == true) {
  // Profile was successfully saved
  // You can reload data or show a success message
}
```

### From Dashboard

Add this to your dashboard action buttons:

```dart
IconButton(
  icon: const Icon(Icons.edit, color: Colors.white70),
  tooltip: 'Edit Profile',
  onPressed: () async {
    await showDialog(
      context: context,
      builder: (context) => const UserProfileModal(),
    );
  },
),
```

## Data Structure

The modal saves data to Firestore in the `users` collection:

```json
{
  "username": "string",
  "email": "string",
  "phone": "string (optional)",
  "handicap": "number (optional)",
  "experienceLevel": "string (optional)"
}
```

## Styling

The modal uses the app's theme colors:
- `AppColors.primary` (Emerald) for primary actions
- `AppColors.surfaceDark` for backgrounds
- `AppColors.error` for validation errors
- Glassmorphism effects for modern look
