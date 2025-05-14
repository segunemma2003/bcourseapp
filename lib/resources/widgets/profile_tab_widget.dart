import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/networking/user_api_service.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/pages/faq_page.dart';
import 'package:flutter_app/resources/pages/help_center_page.dart';
import 'package:flutter_app/resources/pages/payment_details_page.dart';
import 'package:flutter_app/resources/pages/profile_details_page.dart';
import 'package:flutter_app/resources/pages/purchase_history_page.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  // Define state name for Nylo's state management
  static String state = '/profile_tab';

  @override
  createState() => _ProfileTabState();
}

class _ProfileTabState extends NyState<ProfileTab> {
  String userName = "";
  String userEmail = "";
  String userImage = "profile_image.png"; // Path to user image
  bool _isAuthenticated = false;

  UserApiService _userApiService = UserApiService();
  // Set state name for Nylo's state management
  _ProfileTabState() {
    stateName = ProfileTab.state;
  }

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer(
        child: _buildSkeletonLayout(),
      );

  @override
  get init => () async {
        super.init();

        // Check authentication status
        _isAuthenticated = await Auth.isAuthenticated();

        // Load user data if authenticated
        if (_isAuthenticated) {
          await _loadUserData();
        }
      };

  @override
  stateUpdated(data) async {
    if (data == "refresh_profile") {
      await _loadUserData();
    } else if (data == "update_auth_status") {
      _isAuthenticated = await Auth.isAuthenticated();

      if (_isAuthenticated) {
        await _loadUserData();
      } else {
        setState(() {
          userName = "";
          userEmail = "";
        });
      }
    }

    return super.stateUpdated(data);
  }

  Future<void> _loadUserData() async {
    setLoading(true, name: 'fetch_profile');

    try {
      // Get data from Auth
      var userData = await Auth.data();

      if (userData != null) {
        setState(() {
          userName = userData['full_name'] ?? userData['fullName'] ?? "";
          userEmail = userData['email'] ?? "";

          // If there's a profile image in the user data
          if (userData['profile_image'] != null) {
            userImage = userData['profile_image'];
          }
        });
      } else {
        // Attempt to get user from storage
        String? userJson = await NyStorage.read('user');
        if (userJson != null) {
          Map<String, dynamic> storedUser = jsonDecode(userJson);
          setState(() {
            userName = storedUser['full_name'] ?? storedUser['fullName'] ?? "";
            userEmail = storedUser['email'] ?? "";

            // If there's a profile image in the user data
            if (storedUser['profile_image'] != null) {
              userImage = storedUser['profile_image'];
            }
          });
        }
      }
    } catch (e) {
      NyLogger.error('Failed to load user data: $e');

      showToast(
          title: trans("Error"),
          description: trans("Failed to load your profile"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger);
    } finally {
      setLoading(false, name: 'fetch_profile');
    }
  }

  void _navigateToProfileDetails() {
    routeTo(ProfileDetailsPage.path);
  }

  void _navigateToPaymentDetails() {
    routeTo(PaymentDetailsPage.path);
  }

  void _navigateToPurchaseHistory() {
    routeTo(PurchaseHistoryPage.path);
  }

  void _navigateToGetHelp() {
    routeTo(HelpCenterPage.path);
  }

  void _navigateToFaqs() {
    routeTo(FaqPage.path);
  }

  void _navigateToLogin() {
    routeTo(SigninPage.path);
  }

  void _logout() async {
    // Using Nylo's confirmAction for dialogs
    confirmAction(() async {
      await lockRelease('logout', perform: () async {
        setLoading(true, name: 'logout');

        try {
          // Call API Service to logout
          await _userApiService.logout();

          // Clear auth status in Nylo
          await Auth.logout();

          // Update state
          setState(() {
            _isAuthenticated = false;
            userName = "";
            userEmail = "";
          });

          // Show success toast
          showToastSuccess(description: trans("Successfully logged out"));

          // Navigate to first tab
          routeTo(SigninPage.path);
        } catch (e) {
          NyLogger.error('Failed to logout: $e');

          // Show error toast
          showToastDanger(description: trans("Failed to logout"));
        } finally {
          setLoading(false, name: 'logout');
        }
      });
    },
        title: trans("Logout"),
        // description: trans("Are you sure you want to logout?"),
        confirmText: trans("Logout"),
        dismissText: trans("Cancel"));
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withAlpha(77),
                spreadRadius: 1,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              trans("Your Profile"),
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              // Refresh button if authenticated

              IconButton(
                icon: Icon(Icons.refresh, color: Colors.black87),
                onPressed: () => _loadUserData(),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: afterLoad(
          loadingKey: 'fetch_profile',
          child: () => _buildAuthenticatedView(),
        ),
      ),
    );
  }

  Widget _buildAuthenticatedView() {
    return RefreshIndicator(
      onRefresh: _loadUserData,
      child: ListView(
        children: [
          // Profile Header with Avatar
          _buildProfileHeader(),

          // First Personal Section
          _buildSectionTitle("Account"),

          // Profile details
          _buildMenuItem(
            icon: Icons.person_outline,
            title: trans("Profile details"),
            onTap: _navigateToProfileDetails,
          ),

          // Payment details
          _buildMenuItem(
            icon: Icons.credit_card_outlined,
            title: trans("Payment details"),
            onTap: _navigateToPaymentDetails,
          ),

          // Purchase History
          _buildMenuItem(
            icon: Icons.history_outlined,
            title: trans("Purchase History"),
            onTap: _navigateToPurchaseHistory,
            showBottomBorder: false,
          ),

          // Second Section
          SizedBox(height: 8),
          _buildSectionTitle("Support"),

          // Get Help
          _buildMenuItem(
            icon: Icons.chat_bubble_outline_outlined,
            title: trans("Get Help"),
            onTap: _navigateToGetHelp,
          ),

          // FAQs
          _buildMenuItem(
            icon: Icons.question_mark_outlined,
            title: trans("FAQs"),
            onTap: _navigateToFaqs,
            showBottomBorder: false,
          ),

          // Logout Section
          SizedBox(height: 8),
          _buildSectionTitle(""),

          // Logout
          _buildMenuItem(
            icon: Icons.logout,
            title: trans("Logout"),
            onTap: _logout,
            iconColor: Colors.red.shade400,
            showBottomBorder: false,
          ),

          // Version info
          SizedBox(height: 32),
          Align(
            alignment: Alignment.center,
            child: Text(
              "Version 1.0.0",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Spacer(flex: 1),

          // Image
          Image.asset(
            "bro.png",
            width: 150,
            height: 150,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 150,
                height: 150,
                child: Icon(
                  Icons.account_circle,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
              );
            },
          ).localAsset(),

          SizedBox(height: 24),

          // Title
          Text(
            trans("Login to access your profile"),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 8),

          // Subtitle
          Text(
            trans("Sign in to view and manage your account"),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 20),

          // Login Button
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: _navigateToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                trans("Login"),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          Spacer(flex: 1),

          // Version info
          Text(
            "Version 1.0.0",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 24),
      color: Colors.white,
      child: Column(
        children: [
          // Profile Image with Camera Icon
          Stack(
            alignment: Alignment.center,
            children: [
              // Profile Image
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade200,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: userImage.startsWith('http')
                      ? Image.network(
                          userImage,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : "U",
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            );
                          },
                        )
                      : Image.asset(
                          getImageAsset(userImage),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : "U",
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),

              // Camera Icon (positioned at bottom right)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.amber,
                  ),
                  child: Icon(
                    Icons.photo_camera,
                    size: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          // User Name
          Text(
            userName.isNotEmpty ? userName : trans("Guest User"),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: 4),

          // User Email
          Text(
            userEmail.isNotEmpty ? userEmail : trans("Not signed in"),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = Colors.black87,
    bool showBottomBorder = true,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: showBottomBorder
                ? BorderSide(color: Colors.grey.shade200)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // Skeleton layout for loading state
  Widget _buildSkeletonLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: Container(
          color: Colors.white,
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            // Profile header skeleton
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 24),
              color: Colors.white,
              child: Column(
                children: [
                  // Avatar skeleton
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.shade300,
                    ),
                  ),

                  SizedBox(height: 16),

                  // Name skeleton
                  Container(
                    width: 150,
                    height: 20,
                    color: Colors.grey.shade300,
                  ),

                  SizedBox(height: 8),

                  // Email skeleton
                  Container(
                    width: 200,
                    height: 14,
                    color: Colors.grey.shade300,
                  ),
                ],
              ),
            ),

            // Section title skeleton
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
              child: Container(
                width: 80,
                height: 16,
                color: Colors.grey.shade300,
              ),
            ),

            // Menu items skeletons
            for (int i = 0; i < 3; i++)
              Container(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      color: Colors.grey.shade300,
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        height: 14,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
