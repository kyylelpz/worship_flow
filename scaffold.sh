#!/usr/bin/env bash
set -euo pipefail

# --- pubspec deps --------------------------------------------------------
# Replaces the default pubspec.yaml with the WorshipFlow one.
cat > pubspec.yaml <<'EOF'
name: worship_flow
description: WorshipFlow — Every Note for His Glory
publish_to: "none"
version: 0.1.0

environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  go_router: ^14.2.0
  google_fonts: ^6.2.1
  intl: ^0.19.0
  uuid: ^4.4.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
EOF

cat > analysis_options.yaml <<'EOF'
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_single_quotes: true
    always_declare_return_types: true
    unawaited_futures: true
    avoid_print: true
    prefer_final_locals: true
EOF

# --- directory structure -------------------------------------------------
mkdir -p lib/app
mkdir -p lib/core/theme
mkdir -p lib/core/router
mkdir -p lib/core/models
mkdir -p lib/core/mock_data
mkdir -p lib/core/widgets

mkdir -p lib/features/auth/data
mkdir -p lib/features/auth/providers
mkdir -p lib/features/auth/screens

mkdir -p lib/features/groups/data
mkdir -p lib/features/groups/providers
mkdir -p lib/features/groups/screens

mkdir -p lib/features/setlists/data
mkdir -p lib/features/setlists/providers
mkdir -p lib/features/setlists/widgets
mkdir -p lib/features/setlists/screens

mkdir -p lib/features/songs/data
mkdir -p lib/features/songs/providers
mkdir -p lib/features/songs/widgets
mkdir -p lib/features/songs/screens

mkdir -p lib/features/charts/data
mkdir -p lib/features/charts/providers
mkdir -p lib/features/charts/widgets

mkdir -p lib/features/rehearsal/screens
mkdir -p lib/features/rehearsal/widgets

mkdir -p lib/features/live/screens
mkdir -p lib/features/live/widgets

mkdir -p lib/features/profile/screens
mkdir -p lib/features/profile/widgets

# --- entry point + app ---------------------------------------------------
: > lib/main.dart
: > lib/app/bootstrap.dart
: > lib/app/app.dart

# --- core: theme ---------------------------------------------------------
: > lib/core/theme/app_colors.dart
: > lib/core/theme/app_typography.dart
: > lib/core/theme/app_theme.dart
: > lib/core/theme/theme_providers.dart

# --- core: router --------------------------------------------------------
: > lib/core/router/route_paths.dart
: > lib/core/router/app_router.dart
: > lib/core/router/router_refresh.dart

# --- core: models --------------------------------------------------------
: > lib/core/models/user_role.dart
: > lib/core/models/app_user.dart
: > lib/core/models/group_member.dart
: > lib/core/models/worship_group.dart
: > lib/core/models/vocalist_key.dart
: > lib/core/models/arrangement.dart
: > lib/core/models/song.dart
: > lib/core/models/setlist_item.dart
: > lib/core/models/setlist.dart
: > lib/core/models/chart_settings.dart
: > lib/core/models/session_state.dart

# --- core: mock data -----------------------------------------------------
: > lib/core/mock_data/mock_users.dart
: > lib/core/mock_data/mock_groups.dart
: > lib/core/mock_data/mock_songs.dart
: > lib/core/mock_data/mock_setlists.dart

# --- core: shared widgets ------------------------------------------------
: > lib/core/widgets/app_scaffold.dart
: > lib/core/widgets/primary_button.dart
: > lib/core/widgets/section_header.dart
: > lib/core/widgets/status_chip.dart
: > lib/core/widgets/empty_state.dart
: > lib/core/widgets/loading_overlay.dart
: > lib/core/widgets/role_selector_sheet.dart

# --- features: auth ------------------------------------------------------
: > lib/features/auth/data/auth_repository.dart
: > lib/features/auth/providers/auth_providers.dart
: > lib/features/auth/screens/login_screen.dart

# --- features: groups ----------------------------------------------------
: > lib/features/groups/data/group_repository.dart
: > lib/features/groups/providers/group_providers.dart
: > lib/features/groups/screens/group_selection_screen.dart
: > lib/features/groups/screens/group_members_screen.dart

# --- features: setlists --------------------------------------------------
: > lib/features/setlists/data/setlist_repository.dart
: > lib/features/setlists/providers/setlist_providers.dart
: > lib/features/setlists/widgets/setlist_card.dart
: > lib/features/setlists/widgets/upcoming_service_card.dart
: > lib/features/setlists/widgets/setlist_filter_bar.dart
: > lib/features/setlists/screens/setlists_screen.dart
: > lib/features/setlists/screens/setlist_details_screen.dart
: > lib/features/setlists/screens/setlist_editor_screen.dart

# --- features: songs (Phase 2 stubs) ------------------------------------
: > lib/features/songs/data/song_repository.dart
: > lib/features/songs/providers/song_providers.dart
: > lib/features/songs/screens/song_library_screen.dart
: > lib/features/songs/screens/song_details_screen.dart
: > lib/features/songs/screens/song_editor_screen.dart
: > lib/features/songs/widgets/song_card.dart

# --- features: charts (Phase 2 stubs) -----------------------------------
: > lib/features/charts/data/chart_transformer.dart

# --- features: rehearsal / live (Phase 3 stubs) -------------------------
: > lib/features/rehearsal/screens/rehearsal_screen.dart
: > lib/features/live/screens/live_performance_screen.dart

# --- features: profile (Phase 2 stubs) ----------------------------------
: > lib/features/profile/screens/profile_screen.dart
: > lib/features/profile/screens/chart_settings_screen.dart

# --- remove default Flutter counter sample ------------------------------
rm -f test/widget_test.dart

echo "Scaffold created. Now run: flutter pub get"