import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/networking/user_api_service.dart';
import 'signin_page.dart';

class ProfileDetailsPage extends NyStatefulWidget {
  static RouteView path = ("/profile-details", (_) => ProfileDetailsPage());

  ProfileDetailsPage({super.key})
      : super(child: () => _ProfileDetailsPageState());
}

class _ProfileDetailsPageState extends NyPage<ProfileDetailsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  DateTime? _dateOfBirth;
  bool _hasChanges = false;
  Map<String, dynamic>? _originalUserData;
  UserApiService _userApiService = UserApiService();

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer(
        child: _buildSkeletonLayout(),
      );

  @override
  get init => () async {
        super.init();
        await _loadUserData();

        // Add listeners to detect changes
        _nameController.addListener(_checkForChanges);
        _phoneController.addListener(_checkForChanges);
      };

  Future<void> _loadUserData() async {
    setLoading(true, name: 'fetch_profile_details');

    try {
      // Get data from Auth
      var userData = await Auth.data();

      NyLogger.info('Loading user data: $userData');

      if (userData != null) {
        // Store original data for comparison
        _originalUserData = Map<String, dynamic>.from(userData);

        setState(() {
          _nameController.text =
              userData['full_name'] ?? userData['fullName'] ?? "";
          _emailController.text = userData['email'] ?? "";
          _phoneController.text =
              userData['phone_number'] ?? userData['phoneNumber'] ?? "";

          // Parse date of birth if available
          if (userData['date_of_birth'] != null &&
              userData['date_of_birth'] is String) {
            try {
              _dateOfBirth = DateTime.parse(userData['date_of_birth']);
            } catch (e) {
              _dateOfBirth = null;
            }
          }
        });
      } else {
        // Attempt to get user from storage
        String? userJson = await NyStorage.read('user');
        if (userJson != null) {
          try {
            Map<String, dynamic> storedUser = jsonDecode(userJson);
            _originalUserData = Map<String, dynamic>.from(storedUser);

            setState(() {
              _nameController.text =
                  storedUser['full_name'] ?? storedUser['fullName'] ?? "";
              _emailController.text = storedUser['email'] ?? "";
              _phoneController.text =
                  storedUser['phone_number'] ?? storedUser['phoneNumber'] ?? "";

              // Parse date of birth if available
              if (storedUser['date_of_birth'] != null &&
                  storedUser['date_of_birth'] is String) {
                try {
                  _dateOfBirth = DateTime.parse(storedUser['date_of_birth']);
                } catch (e) {
                  _dateOfBirth = null;
                }
              }
            });
          } catch (e) {
            NyLogger.error('Error parsing user data: $e');
            showToastWarning(
                description: trans("Could not parse profile data"));
          }
        } else {
          showToastWarning(description: trans("Could not load profile data"));
        }
      }

      // Check if changes are detected initially
      _checkForChanges();
    } catch (e) {
      NyLogger.error('Failed to load user data: $e');

      showToast(
          title: trans("Error"),
          description: trans("Failed to load profile details"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger);
    } finally {
      setLoading(false, name: 'fetch_profile_details');
    }
  }

  void _checkForChanges() {
    if (_originalUserData == null) return;

    // Debug logging
    NyLogger.info('Checking for changes:');
    NyLogger.info(
        'Original name: ${_originalUserData!['full_name'] ?? _originalUserData!['fullName'] ?? ""}');
    NyLogger.info('Current name: ${_nameController.text}');
    NyLogger.info(
        'Original phone: ${_originalUserData!['phone_number'] ?? _originalUserData!['phoneNumber'] ?? ""}');
    NyLogger.info('Current phone: ${_phoneController.text}');

    final bool nameChanged = _nameController.text !=
        (_originalUserData!['full_name'] ??
            _originalUserData!['fullName'] ??
            "");

    final bool phoneChanged = _phoneController.text !=
        (_originalUserData!['phone_number'] ??
            _originalUserData!['phoneNumber'] ??
            "");

    final bool dateChanged = _dateChanged();

    final bool hasChanges = nameChanged || phoneChanged || dateChanged;

    NyLogger.info(
        'Has changes: $hasChanges (name: $nameChanged, phone: $phoneChanged, date: $dateChanged)');

    if (hasChanges != _hasChanges) {
      setState(() {
        _hasChanges = hasChanges;
      });
    }
  }

  bool _dateChanged() {
    if (_originalUserData == null) return false;

    String? originalDateString = _originalUserData!['date_of_birth'];
    DateTime? originalDate;

    if (originalDateString != null && originalDateString.isNotEmpty) {
      try {
        originalDate = DateTime.parse(originalDateString);
      } catch (e) {
        originalDate = null;
      }
    }

    if (originalDate == null && _dateOfBirth == null) return false;
    if (originalDate == null && _dateOfBirth != null) return true;
    if (originalDate != null && _dateOfBirth == null) return true;

    return !_areDatesEqual(originalDate!, _dateOfBirth!);
  }

  bool _areDatesEqual(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime.now().subtract(Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.amber,
              onPrimary: Colors.black,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.amber,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null &&
        (_dateOfBirth == null || !_areDatesEqual(picked, _dateOfBirth!))) {
      setState(() {
        _dateOfBirth = picked;
      });
      // Make sure to call _checkForChanges after updating the date
      _checkForChanges();
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return trans("Set date of birth");
    return DateFormat('MMM d, yyyy').format(date);
  }

  Future<void> _saveChanges() async {
    // Log for debugging
    NyLogger.info('Save changes button pressed');
    NyLogger.info('Has changes: $_hasChanges');

    if (!_hasChanges) {
      NyLogger.info('No changes detected, skipping save');
      return;
    }

    await lockRelease('save_profile', perform: () async {
      setLoading(true, name: 'saving_profile');

      try {
        // Prepare the formatted date in YYYY-MM-DD format as required by the API
        String? formattedDate;
        if (_dateOfBirth != null) {
          formattedDate = DateFormat('yyyy-MM-dd').format(_dateOfBirth!);
          NyLogger.info('Formatted date: $formattedDate');
        }

        NyLogger.info(
            'Updating profile with name: ${_nameController.text}, phone: ${_phoneController.text}, date: $formattedDate');

        // Call the API to update the profile
        final updatedUserData = await _userApiService.updateProfile(
          fullName: _nameController.text,
          phoneNumber: _phoneController.text,
          dateOfBirth: formattedDate,
        );

        NyLogger.info('Profile updated successfully: $updatedUserData');

        // Update local data
        _originalUserData = updatedUserData;

        // Update stored user data
        await storageSave("user", jsonEncode(updatedUserData));

        // Update Auth data to reflect changes
        await Auth.authenticate(data: updatedUserData);

        // Update profile tab state
        updateState('/profile_tab', data: "refresh_profile");

        // Show success message
        showToastSuccess(
            description: trans("Profile details updated successfully"));

        setState(() {
          _hasChanges = false;
        });
      } catch (e) {
        NyLogger.error('Failed to update profile: $e');

        showToastDanger(description: trans("Failed to update profile details"));
      } finally {
        setLoading(false, name: 'saving_profile');
      }
    });
  }

  Future<void> _signOut() async {
    // Using Nylo's confirmAction for dialogs
    confirmAction(() async {
      await lockRelease('logout', perform: () async {
        setLoading(true, name: 'logout');

        try {
          // Call API Service to logout
          await _userApiService.logout();

          // Clear auth status in Nylo
          await Auth.logout();

          // Show success toast
          showToastSuccess(description: trans("Successfully logged out"));

          // Navigate to sign in page
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
        confirmText: trans("Logout"),
        dismissText: trans("Cancel"));
  }

  Future<void> _deleteAccount() async {
    // Using Nylo's confirmAction for dialogs
    confirmAction(() async {
      await lockRelease('delete_account', perform: () async {
        setLoading(true, name: 'delete_account');

        try {
          // Call API Service to delete account
          await _userApiService.deleteAccount();

          // Clear auth status in Nylo
          await Auth.logout();

          // Show success toast
          showToastSuccess(description: trans("Account successfully deleted"));

          // Navigate to sign in page
          routeTo(SigninPage.path);
        } catch (e) {
          NyLogger.error('Failed to delete account: $e');

          // Show error toast
          showToastDanger(description: trans("Failed to delete account"));
        } finally {
          setLoading(false, name: 'delete_account');
        }
      });
    },
        title: trans("Delete Account"),
        confirmText: trans("Delete"),
        dismissText: trans("Cancel"));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          trans("Profile Details"),
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData,
        child: afterLoad(
          loadingKey: 'fetch_profile_details',
          child: () => afterLoad(
            loadingKey: 'logout',
            child: () => afterLoad(
              loadingKey: 'delete_account',
              child: () => SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 20),
                    // Form fields
                    _buildFormSection(),

                    // Save button with more spacing
                    SizedBox(height: 32),
                    _buildSaveButton(),

                    // Account options with more spacing
                    SizedBox(height: 48),
                    _buildAccountOptions(),

                    // Debug section for development
                    if (getEnv('APP_DEBUG') == 'true') _buildDebugSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full Name
          Text(
            trans("Full Name"),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _nameController,
            style: TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: trans("Enter your full name"),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.amber),
              ),
            ),
            onChanged: (value) {
              // Additional check when text changes directly
              _checkForChanges();
            },
          ),

          SizedBox(height: 20),

          // Email Address (non-editable)
          Text(
            trans("Email Address"),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _emailController,
            enabled: false, // Make it non-editable
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            decoration: InputDecoration(
              hintText: trans("Your email address"),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              suffixIcon:
                  Icon(Icons.lock_outline, size: 16, color: Colors.grey),
            ),
          ),

          SizedBox(height: 20),

          // Phone Number
          Text(
            trans("Phone Number"),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: trans("Enter your phone number"),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.amber),
              ),
            ),
            onChanged: (value) {
              // Additional check when text changes directly
              _checkForChanges();
            },
          ),

          SizedBox(height: 20),

          // Date of Birth
          Text(
            trans("Date of Birth"),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 8),
          GestureDetector(
            onTap: () => _selectDate(context),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDate(_dateOfBirth),
                      style: TextStyle(
                        color: _dateOfBirth == null
                            ? Colors.grey.shade500
                            : Colors.black,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today_outlined,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: _hasChanges ? _saveChanges : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasChanges ? Colors.amber : Colors.grey.shade200,
          foregroundColor: _hasChanges ? Colors.black : Colors.grey.shade500,
          disabledBackgroundColor: Colors.grey.shade200,
          disabledForegroundColor: Colors.grey.shade500,
          elevation: _hasChanges ? 1 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.symmetric(vertical: 16),
          minimumSize: Size(double.infinity, 54),
        ),
        child: Text(
          trans("Save Changes"),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildAccountOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            trans("Account"),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),

        // Sign Out Option
        InkWell(
          onTap: _signOut,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.logout,
                  size: 24,
                  color: Colors.black87,
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    trans("Logout"),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),

        // Delete Account Option
        InkWell(
          onTap: _deleteAccount,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 24,
                  color: Colors.red,
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    trans("Delete Account"),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.red,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Debug section - only visible in debug mode
  Widget _buildDebugSection() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("DEBUG INFO", style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text("Has Changes: $_hasChanges"),
          Text("Name Field: ${_nameController.text}"),
          Text("Phone Field: ${_phoneController.text}"),
          Text(
              "Date of Birth: ${_dateOfBirth != null ? DateFormat('yyyy-MM-dd').format(_dateOfBirth!) : 'Not set'}"),
          Text(
              "Original Name: ${_originalUserData?['full_name'] ?? _originalUserData?['fullName'] ?? 'Not set'}"),
          Text(
              "Original Phone: ${_originalUserData?['phone_number'] ?? _originalUserData?['phoneNumber'] ?? 'Not set'}"),
          Text(
              "Original Date: ${_originalUserData?['date_of_birth'] ?? 'Not set'}"),
          SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              showToastInfo(description: "Force checking changes");
              _checkForChanges();
            },
            child: Text("Force Check Changes"),
          ),
        ],
      ),
    );
  }

  // Skeleton layout for loading state
  Widget _buildSkeletonLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.transparent),
          onPressed: null,
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20),

              // Form field skeletons
              for (int i = 0; i < 4; i++) ...[
                Container(
                  width: 80,
                  height: 16,
                  color: Colors.grey.shade300,
                ),
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                SizedBox(height: 20),
              ],

              // Save button skeleton
              SizedBox(height: 32),
              Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),

              // Account options skeleton
              SizedBox(height: 48),
              Container(
                width: 80,
                height: 16,
                color: Colors.grey.shade300,
              ),
              SizedBox(height: 8),
              for (int i = 0; i < 2; i++) ...[
                Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
