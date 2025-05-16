import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/verify_o_t_p_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/networking/user_api_service.dart';

class ForgotPasswordPage extends NyStatefulWidget {
  static RouteView path = ("/forgot-password", (_) => ForgotPasswordPage());

  ForgotPasswordPage({super.key})
      : super(child: () => _ForgotPasswordPageState());
}

class _ForgotPasswordPageState extends NyPage<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  get init => () {};

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    updateState(() => _isLoading = true);

    try {
      // Call the updated API method that returns response data
      var response =
          await api<UserApiService>((request) => request.requestPasswordReset(
                email: _emailController.text.trim(),
              ));

      if (response != null) {
        // Show success message with expiry info
        String message = response['message'] ?? 'OTP sent successfully';
        String? expiryInfo = response['otp_expires_in'];

        if (expiryInfo != null) {
          message += '\nOTP expires in: $expiryInfo';
        }

        showToast(
          title: "Success",
          description: message,
          style: ToastNotificationStyleType.success,
        );

        // Navigate to OTP verification screen
        routeTo(VerifyOTPPage.path, data: _emailController.text.trim());
      }
    } catch (e) {
      showToast(
        title: "Error",
        description: e.toString().replaceAll('Exception: ', ''),
        style: ToastNotificationStyleType.danger,
      );
    } finally {
      updateState(() => _isLoading = false);
    }
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Forgot Password",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Enter your Email address to change your password",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 40),
                Text(
                  "Email Address",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: "example@email.com",
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your email";
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(value)) {
                      return "Please enter a valid email";
                    }
                    return null;
                  },
                ),
                Spacer(),
                Container(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE8E55C),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.black)
                        : Text(
                            "Continue",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
