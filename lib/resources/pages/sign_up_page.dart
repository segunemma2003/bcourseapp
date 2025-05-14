import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/widgets/logo_widget.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter/gestures.dart';
import '../../app/networking/user_api_service.dart';
import '../../utils/system_util.dart';

class SignUpPage extends NyStatefulWidget {
  static RouteView path = ("/sign-up", (_) => SignUpPage());

  SignUpPage({super.key}) : super(child: () => _SignUpPageState());
}

class _SignUpPageState extends NyPage<SignUpPage> {
  @override
  get init => () {};

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _agreeToTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Add UserApiService
  UserApiService _userApiService = UserApiService();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 5),
                // Logo
                Center(
                  child: Logo(
                    height: 70.0,
                    width: 150.0,
                  ),
                ),
                const SizedBox(height: 8),

                // Header text
                Text(
                  'Create an Account'.tr(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign up now to get started with your account'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),

                // Full Name
                _buildFieldLabel('Full Name'.tr()),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _fullNameController,
                  hintText: 'John Doe'.tr(),
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Please enter your full name'.tr()
                      : null,
                ),

                const SizedBox(height: 16),
                // Email
                _buildFieldLabel('Email Address'.tr()),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _emailController,
                  hintText: 'example@email.com'.tr(),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Please enter your email'.tr();
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(value!)) {
                      return 'Please enter a valid email'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),
                // Phone
                _buildFieldLabel('Phone Number'.tr()),
                const SizedBox(height: 8),
                _buildPhoneField(),

                const SizedBox(height: 16),
                // Password
                _buildFieldLabel('Password'.tr()),
                const SizedBox(height: 8),
                _buildPasswordField(
                  controller: _passwordController,
                  hintText: 'Enter password'.tr(),
                  obscureText: _obscurePassword,
                  toggleObscure: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Please enter a password'.tr();
                    }
                    if ((value?.length ?? 0) < 6) {
                      return 'Password must be at least 6 characters'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),
                // Confirm Password
                _buildFieldLabel('Confirm Password'.tr()),
                const SizedBox(height: 8),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  hintText: 'Re-Enter password'.tr(),
                  obscureText: _obscureConfirmPassword,
                  toggleObscure: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Please confirm your password'.tr();
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),
                // Terms and Conditions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreeToTerms,
                        onChanged: (value) =>
                            setState(() => _agreeToTerms = value ?? false),
                        activeColor: const Color(0xFFFFEB3B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.black,
                          ),
                          children: [
                            TextSpan(
                                style: TextStyle(fontSize: 10),
                                text: 'I have read and agree the '.tr()),
                            TextSpan(
                              text: 'Terms and Conditions'.tr(),
                              style: TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  // Navigate to terms and conditions page
                                },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                // Sign Up Button (using afterNotLocked like in the signin page)
                afterNotLocked(
                  'signup',
                  child: () => _buildSignUpButton(),
                  loading: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

                const SizedBox(height: 8),

                // Google Button
                afterNotLocked(
                  'google_signup',
                  child: () => _buildGoogleButton(),
                  loading: SizedBox.shrink(),
                ),

                const SizedBox(height: 20),
                // Already have account
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                      ),
                      children: [
                        TextSpan(
                            text: 'Already Have an Account? '.tr(),
                            style: TextStyle(fontSize: 13)),
                        TextSpan(
                          text: 'Sign In'.tr(),
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(fontSize: 11),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: const Color(0xFFFFEB3B)),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback toggleObscure,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      style: TextStyle(fontSize: 11),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: const Color(0xFFFFEB3B)),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.grey,
          ),
          onPressed: toggleObscure,
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      height: 45,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Country code section
          Container(
            width: 50,
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: Text(
                '+91',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),

          // Vertical divider
          Container(
            width: 1,
            height: 30,
            color: Colors.grey.shade300,
          ),

          // Phone number field
          Expanded(
            child: TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(fontSize: 14),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Please enter your phone number'.tr();
                }
                if ((value?.length ?? 0) < 10) {
                  return 'Please enter a valid phone number'.tr();
                }
                return null;
              },
              decoration: InputDecoration(
                hintText: '10101 01010',
                hintStyle: TextStyle(color: Colors.grey),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: InputBorder.none, // Remove borders
                enabledBorder: InputBorder.none, // Remove borders
                focusedBorder: InputBorder.none, // Remove borders
                errorBorder: InputBorder.none, // Remove borders
                disabledBorder: InputBorder.none, // Remove borders
                focusedErrorBorder: InputBorder.none, // Remove borders
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignUpButton() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFFFFEB3B),
      ),
      child: TextButton(
        onPressed: _handleSignUp,
        style: TextButton.styleFrom(
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(
          'Sign Up'.tr(), // Changed from 'Sign In' to 'Sign Up'
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextButton.icon(
        onPressed: _handleGoogleSignIn,
        icon: Image.asset(
          "devicon_google.png",
          height: 16,
          width: 16,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.g_mobiledata, size: 24),
        ).localAsset(),
        label: Text(
          'Google'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignUp() async {
    if (!_agreeToTerms) {
      showToastDanger(
        description: 'Please agree to the terms and conditions'.tr(),
      );
      return;
    }

    if (_formKey.currentState?.validate() ?? false) {
      await lockRelease('signup', perform: () async {
        try {
          // Call the API service to register
          await _userApiService.register(
            email: _emailController.text,
            password: _passwordController.text,
            fullName: _fullNameController.text,
            phoneNumber: '+91${_phoneController.text}', // Include country code
          );

          // Show success toast
          showToastSuccess(
            description: 'Account created successfully!'.tr(),
          );

          // Preload essential data
          await preloadEssentialData();

          // Navigate to the main app
          routeTo(BaseNavigationHub.path,
              navigationType: NavigationType.pushAndRemoveUntil,
              removeUntilPredicate: (route) => false);
        } catch (e) {
          // Show error toast
          print(e.toString());
          showToastDanger(
            description: e.toString(),
          );
        }
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    await lockRelease('google_signup', perform: () async {
      try {
        // Call the API service for Google sign in
        await _userApiService.loginWithGoogle();

        // Show success toast
        showToastSuccess(
          description: 'Google sign in successful'.tr(),
        );

        // Preload essential data
        await preloadEssentialData();

        // Navigate to the main app
        routeTo(BaseNavigationHub.path,
            navigationType: NavigationType.pushAndRemoveUntil,
            removeUntilPredicate: (route) => false);
      } catch (e) {
        // Show error toast
        showToastDanger(
          description: e.toString(),
        );
      }
    });
  }
}
