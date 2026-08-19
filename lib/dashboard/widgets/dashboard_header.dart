import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/local/auth_storage.dart';
import '../../theme/app_colors.dart';
import '../models/dashboard_data.dart';

/// The orange gradient top bar shared by every dashboard tab: avatar + welcome
/// name + notification bell, with an optional search field and filter button.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    this.showSearch = false,
    this.showFilter = false,
    this.showProfile = true,
    this.title,
    this.onBack,
    this.onFilter,
    this.onSearchChanged,
    this.searchController,
    this.onSearchClear,
  });

  final bool showSearch;
  final bool showFilter;
  // When false, the avatar + "Welcome" + name row is hidden (used on the View
  // All screen, where [title] is shown instead).
  final bool showProfile;
  // Shown (with the notification bell) in place of the profile row when
  // [showProfile] is false — e.g. "All Leads".
  final String? title;
  // When set, a white back arrow is shown before [title].
  final VoidCallback? onBack;
  final VoidCallback? onFilter;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;
  final VoidCallback? onSearchClear;

  @override
  Widget build(BuildContext context) {
    final user = DashboardData.user;
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, showSearch ? 18 : 16),
          child: Column(
            children: [
              if (showProfile)
                Row(
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: Colors.white,
                      backgroundImage:
                          const AssetImage(AppAssets.profileAvatar),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Welcome',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // Live name: rebuilds when the session changes (login
                          // or a profile-name edit) via AuthStorage.revision.
                          ValueListenableBuilder<int>(
                            valueListenable: AuthStorage.instance.revision,
                            builder: (_, _, _) {
                              final sessionUser =
                                  AuthStorage.instance.current?.user;
                              final displayName =
                                  (sessionUser?.fullName.trim().isNotEmpty ??
                                          false)
                                      ? sessionUser!.fullName
                                      : user.name;
                              return Text(
                                displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    _NotificationBell(count: user.notifications),
                  ],
                ),
              // No profile row → show the page title + notification bell instead.
              if (!showProfile && title != null)
                Row(
                  children: [
                    if (onBack != null)
                      // Larger tap target (the bare 20px icon was easy to miss,
                      // so back "sometimes" didn't fire). Padding doubles as the
                      // gap before the title.
                      GestureDetector(
                        onTap: onBack,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(0, 8, 16, 8),
                          child: Icon(Icons.arrow_back_ios_new,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _NotificationBell(count: user.notifications),
                  ],
                ),
              if (showSearch) ...[
                if (showProfile || title != null) const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SearchField(
                        onChanged: onSearchChanged,
                        controller: searchController,
                        onClear: onSearchClear,
                      ),
                    ),
                    if (showFilter) ...[
                      const SizedBox(width: 12),
                      _FilterButton(onTap: onFilter),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const AppIcon(AppAssets.notification, size: 22, color: Colors.white),
          if (count > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                decoration: const BoxDecoration(
                  color: AppColors.purpleDeep,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({this.onChanged, this.controller, this.onClear});
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    // Show a tappable cancel (X) icon while there's a query, else the search
    // icon. Tapping X clears the field and closes the results overlay.
    final hasText = controller?.text.trim().isNotEmpty ?? false;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.none,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search by Lead ID or Name',
          hintStyle: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          // Same Padding + 20px icon whether search or close, so swapping them
          // never re-lays-out the field (text stays put). Tap only clears when
          // there's a query.
          suffixIcon: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: hasText ? onClear : null,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: hasText
                  ? const Icon(Icons.close, size: 20, color: Color(0xFF555555))
                  : const AppIcon(
                      AppAssets.search,
                      size: 20,
                      color: Color(0xFF555555),
                    ),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 20,
            minHeight: 20,
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: const AppIcon(
            AppAssets.filter,
            size: 21,
            color: AppColors.purpleDeep,
          ),
        ),
      ),
    );
  }
}
