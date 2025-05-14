import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/pages/forgot_password_page.dart';
import 'package:flutter_app/resources/pages/sign_up_page.dart';
import 'package:flutter_app/utils/system_util.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/networking/user_api_service.dart';
import '../../app/providers/api_service_provider.dart';
import '../widgets/logo_widget.dart';

class SigninPage extends NyStatefulWidget {
  static RouteView path = ("/signin", (_) => SigninPage());

  SigninPage({super.key}) : super(child: () => _SigninPageState());
}

class _SigninPageState extends NyPage<SigninPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  UserApiService _userApiService = UserApiService();
  @override
  get init => () {};

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
                const SizedBox(height: 40),
                // Logo
                Center(
                  child: Logo(
                    height: 70.0,
                    width: 150.0,
                  ),
                ),
                const SizedBox(height: 30),

                // Header text
                Text(
                  'Log in to your Account'.tr(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome back, please enter your details'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 30),

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
                    if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(value!)) {
                      return 'Please enter a valid email'.tr();
                    }
                    return null;
                  },
                ),

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
                    return null;
                  },
                ),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      // Navigate to forgot password page
                      routeTo(ForgotPasswordPage.path);
                    },
                    child: Text(
                      'Forgot password?'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // Sign In Button
                afterNotLocked(
                  'signin',
                  child: () => _buildSignInButton(),
                  loading: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),

                const SizedBox(height: 16),

                // Or divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR'.tr(),
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),

                const SizedBox(height: 16),

                // Google Button
                afterNotLocked(
                  'google_signin',
                  child: () => _buildGoogleButton(),
                  loading: SizedBox.shrink(),
                ),

                const SizedBox(height: 30),
                // Don't have account
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                      ),
                      children: [
                        TextSpan(
                          text: 'Don\'t Have an Account? '.tr(),
                          style: TextStyle(fontSize: 13),
                        ),
                        TextSpan(
                          text: 'Sign Up'.tr(),
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              // Navigate to sign up page
                              routeTo(SignUpPage.path);
                            },
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
      style: TextStyle(fontSize: 14),
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
          borderSide: BorderSide(color: Colors.grey.shade300),
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
      style: TextStyle(fontSize: 14),
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
          borderSide: BorderSide(color: Colors.grey.shade300),
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

  Widget _buildSignInButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFFFFEB3B),
      ),
      child: TextButton(
        onPressed: _handleSignIn,
        style: TextButton.styleFrom(
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(
          'Sign In'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextButton.icon(
        onPressed: _handleGoogleSignIn,
        icon: Image.asset(
          "devicon_google.png",
          height: 20,
          width: 20,
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

  Future<void> _handleSignIn() async {
    if (_formKey.currentState?.validate() ?? false) {
      await lockRelease('signin', perform: () async {
        try {
          // Call the API service to log in
          await _userApiService.login(
            email: _emailController.text,
            password: _passwordController.text,
          );

          // Show success toast
          showToastSuccess(
            description: 'Successfully signed in'.tr(),
          );

          // Preload essential data
          // await AppBootstrap.refreshData();

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
    await lockRelease('google_signin', perform: () async {
      try {
        // Call the API service for Google sign in
        await _userApiService.loginWithGoogle();

        // Show success toast
        showToastSuccess(
          description: 'Google sign in successful'.tr(),
        );

        // Preload essential data
        // await AppBootstrap.refreshData();
        // await preloadEssentialData();

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
