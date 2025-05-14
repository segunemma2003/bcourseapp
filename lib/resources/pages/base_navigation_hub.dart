import 'package:flutter/material.dart';
import 'package:flutter_app/resources/widgets/courses_tab_widget.dart';
import 'package:flutter_app/resources/widgets/explore_tab_widget.dart';
import 'package:flutter_app/resources/widgets/profile_tab_widget.dart';
import 'package:flutter_app/resources/widgets/search_tab_widget.dart';
import 'package:flutter_app/resources/widgets/wishlist_tab_widget.dart';
import 'package:nylo_framework/nylo_framework.dart';

class BaseNavigationHub extends NyStatefulWidget with BottomNavPageControls {
  static RouteView path = ("/base", (_) => BaseNavigationHub());

  BaseNavigationHub()
      : super(
            child: () => _BaseNavigationHubState(),
            stateName: path.stateName());

  /// State actions
  static NavigationHubStateActions stateActions =
      NavigationHubStateActions(path.stateName());
}

class _BaseNavigationHubState extends NavigationHub<BaseNavigationHub> {
  /// Layouts:
  /// - [NavigationHubLayout.bottomNav] Bottom navigation
  /// - [NavigationHubLayout.topNav] Top navigation
  /// - [NavigationHubLayout.journey] Journey navigation
  NavigationHubLayout? layout = NavigationHubLayout.bottomNav(
    backgroundColor: Colors.white,
    elevation: 8.0,
    selectedItemColor: Colors.amber,
    unselectedItemColor: Colors.grey,
    showSelectedLabels: true,
    showUnselectedLabels: true,
    // Add type and color for active background
    type: BottomNavigationBarType.shifting,
  );

  /// Should the state be maintained
  @override
  bool get maintainState => true;

  /// Navigation pages
  _BaseNavigationHubState()
      : super(() async {
          /// * Creating Navigation Tabs
          /// [Navigation Tabs] 'dart run nylo_framework:main make:stateful_widget home_tab,settings_tab'
          /// [Journey States] 'dart run nylo_framework:main make:journey_widget welcome_tab,users_dob,users_info --parent=Base'
          return {
            0: NavigationTab(
              title: "Explore",
              page: ExploreTab(),
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore, color: Colors.amber),
            ),
            1: NavigationTab(
              title: "Search",
              page: SearchTab(),
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search, color: Colors.amber),
            ),
            2: NavigationTab(
              title: "My Courses",
              page: CoursesTab(),
              icon: Icon(Icons.play_circle_outline),
              activeIcon: Icon(Icons.play_circle, color: Colors.amber),
            ),
            3: NavigationTab(
              title: "Wishlist",
              page: WishlistTab(),
              icon: Icon(Icons.star_border),
              activeIcon: Icon(Icons.star, color: Colors.amber),
            ),
            4: NavigationTab(
              title: "Profile",
              page: ProfileTab(),
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person, color: Colors.amber),
            ),
          };
        });

  /// Handle the tap event
  @override
  onTap(int index) {
    super.onTap(index);
  }
}
