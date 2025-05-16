import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/new_password_page.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter/services.dart';

import '../../app/networking/user_api_service.dart';

class VerifyOTPPage extends NyStatefulWidget {
  static RouteView path = ("/verify-otp", (context) => VerifyOTPPage());

  VerifyOTPPage({super.key}) : super(child: () => _VerifyOTPPageState());
}

class _VerifyOTPPageState extends NyPage<VerifyOTPPage> {
  final List<TextEditingController> _otpControllers =
      List.generate(4, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (index) => FocusNode());
  bool _isLoading = false;
  String? email;

  @override
  get init => () {
        // Get email from previous screen
        email = widget.data() as String?;
      };

  String get _otp =>
      _otpControllers.map((controller) => controller.text).join();

  Future<void> _handleVerify() async {
    if (_otp.length != 4) {
      showToast(
        title: "Invalid OTP",
        description: "Please enter all 4 digits",
        style: ToastNotificationStyleType.warning,
      );
      return;
    }

    if (email == null) {
      showToast(
        title: "Error",
        description: "Email not found. Please try again.",
        style: ToastNotificationStyleType.danger,
      );
      return;
    }

    updateState(() => _isLoading = true);

    try {
      // Call the separate verify OTP endpoint
      var response = await api<UserApiService>((request) => request.verifyOTP(
            email: email!,
            otp: _otp,
          ));

      if (response != null && response['otp_verified'] == true) {
        // Store OTP and email for the next screen
        await storageSave('temp_otp', _otp);
        await storageSave('temp_email', email);

        showToast(
          title: "Success",
          description: response['message'] ?? 'OTP verified successfully',
          style: ToastNotificationStyleType.success,
        );

        // Navigate to new password screen
        routeTo(NewPasswordPage.path);
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

  Future<void> _resendCode() async {
    if (email == null) return;

    try {
      var response =
          await api<UserApiService>((request) => request.requestPasswordReset(
                email: email!,
              ));

      if (response != null) {
        String message = response['message'] ?? 'OTP resent successfully';
        String? expiryInfo = response['otp_expires_in'];

        if (expiryInfo != null) {
          message += '\nOTP expires in: $expiryInfo';
        }

        showToast(
          title: "OTP Resent",
          description: message,
          style: ToastNotificationStyleType.success,
        );

        // Clear current OTP fields
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } catch (e) {
      showToast(
        title: "Error",
        description: e.toString().replaceAll('Exception: ', ''),
        style: ToastNotificationStyleType.danger,
      );
    }
  }

  Widget _buildOTPField(int index) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          counterText: '',
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (value) {
          if (value.isNotEmpty && index < 3) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }

          // Auto-verify when all fields are filled
          if (_otp.length == 4) {
            setState(() {});
          }
        },
      ),
    );
  }

  @override
  Widget view(BuildContext context) {
    final phoneNumber = "09033807618"; // This should come from your API/storage

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Verify your number",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "We've sent you a 4-digit code to $phoneNumber via SMS",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 40),
              Text(
                "Enter OTP",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(4, (index) => _buildOTPField(index)),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    "Didn't receive OTP? ",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  GestureDetector(
                    onTap: _resendCode,
                    child: Text(
                      "Resend code",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Spacer(),
              Container(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      _otp.length == 4 && !_isLoading ? _handleVerify : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _otp.length == 4 ? Color(0xFFE8E55C) : Colors.grey[300],
                    foregroundColor:
                        _otp.length == 4 ? Colors.black : Colors.grey[600],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.black)
                      : Text(
                          "Verify",
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
    );
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}
