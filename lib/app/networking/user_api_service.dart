import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/utils/system_util.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class UserApiService extends NyApiService {
  UserApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  Future<dynamic> register({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
  }) async {
    return await network(
        request: (request) => request.post(
              "/auth/registration/",
              data: {
                "email": email,
                "full_name": fullName,
                "phone_number": phoneNumber,
                "password1": password,
                "password2": password, // Your API expects both password fields
              },
            ),
        handleSuccess: (Response response) async {
          // Store user token and data
          final responseData = response.data;
          if (responseData['key'] != null) {
            await backpackSave('auth_token', responseData['key']);

            if (responseData['user'] != null) {
              await storageSave("user", responseData['user']);
              await Auth.authenticate(data: responseData['user']);
            }
          }
          return responseData;
        },
        handleFailure: (DioException dioError) {
          // Extract error message from response
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            String errorMessage = "Registration failed";

            if (errors.containsKey('email')) {
              errorMessage = errors['email'][0];
            } else if (errors.containsKey('password1')) {
              errorMessage = errors['password1'][0];
            } else if (errors.containsKey('non_field_errors')) {
              errorMessage = errors['non_field_errors'][0];
            }

            throw Exception(errorMessage);
          }
          throw Exception("Registration failed: ${dioError.message}");
        });
  }

  Future<dynamic> login({
    required String email,
    required String password,
  }) async {
    return await network(
        request: (request) => request.post(
              "/auth/login/",
              data: {
                "email": email,
                "password": password,
              },
            ),
        handleSuccess: (Response response) async {
          // Store user token and data
          final responseData = response.data;
          print(responseData);
          if (responseData['key'] != null) {
            await backpackSave('auth_token', responseData['key']);
            if (responseData['user'] != null) {
              await storageSave("user", responseData['user']);
              print("user----------------------");
              print(responseData);
              await Auth.authenticate(data: responseData['user']);
              Map user = await Auth.data();

              print(user);
              await preloadEssentialData();
            }
          }
          return responseData;
        },
        handleFailure: (DioException dioError) {
          // Extract error message from response
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            String errorMessage = "Login failed";

            if (errors.containsKey('email')) {
              errorMessage = errors['email'][0];
            } else if (errors.containsKey('password')) {
              errorMessage = errors['password'][0];
            } else if (errors.containsKey('non_field_errors')) {
              errorMessage = errors['non_field_errors'][0];
            }
            print(errorMessage.toString());
            throw Exception(errorMessage);
          }
          throw Exception("Login failed: ${dioError.message}");
        });
  }

  Future<dynamic> loginWithGoogle() async {
    try {
      // Trigger the Google Sign In process
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in process
        throw Exception("Google sign-in canceled");
      }

      // Get authentication data from Google
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String accessToken = googleAuth.accessToken!;
      final String? idToken = googleAuth.idToken;

      return await network(
          request: (request) => request.post(
                "/auth/google/",
                data: {
                  "access_token": accessToken,
                  "id_token": idToken, // Optional according to your API docs
                },
              ),
          handleSuccess: (Response response) async {
            // Store user token and data
            final responseData = response.data;
            if (responseData['key'] != null) {
              await backpackSave('auth_token', responseData['key']);
              if (responseData['user'] != null) {
                await storageSave("user", responseData['user']);
                await Auth.authenticate(data: responseData['user']);
                await preloadEssentialData();
              }
            }
            return responseData;
          },
          handleFailure: (DioException dioError) {
            // Extract error message from response
            if (dioError.response?.data != null) {
              final errors = dioError.response!.data;
              String errorMessage = "Google sign-in failed";

              if (errors.containsKey('error')) {
                errorMessage = errors['error'];
              } else if (errors.containsKey('non_field_errors')) {
                errorMessage = errors['non_field_errors'][0];
              }

              throw Exception(errorMessage);
            }
            throw Exception("Google sign-in failed: ${dioError.message}");
          });
    } catch (e) {
      if (e is DioException) {
        throw Exception("Google sign-in failed: ${e.message}");
      }
      throw Exception(e.toString());
    }
  }

  /// Log out user
  Future<bool> logout() async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      return true; // Already logged out
    }

    return await network(
        request: (request) => request.post("/auth/logout/", data: {}),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Clean up local storage
          await backpackDelete('auth_token');
          await storageDelete("user");
          await Auth.logout();
          if (_googleSignIn.currentUser != null) {
            await _googleSignIn.signOut();
            await Auth.logout();
          }

          return true;
        },
        handleFailure: (DioException dioError) async {
          // Still clear local data on error
          await backpackDelete('auth_token');
          await storageDelete("user");
          return true;
        });
  }

  /// Get current user data
  Future<dynamic> getCurrentUser() async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.get(
              "/auth/user/",
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          final userData = response.data;
          await storageSave("user", jsonEncode(userData));

          return userData;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to get user data: ${dioError.message}");
        });
  }

  /// Request password reset (OTP)
  Future<bool> requestPasswordReset({required String email}) async {
    return await network(
        request: (request) => request.post(
              "/auth/forgot-password/",
              data: {
                "email": email,
              },
            ),
        handleSuccess: (Response response) async {
          await storageSave("forgot_email", email);
          return true;
        },
        handleFailure: (DioException dioError) {
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors.containsKey('error')) {
              throw Exception(errors['error']);
            }
          }
          throw Exception(
              "Failed to request password reset: ${dioError.message}");
        });
  }

  /// Verify OTP and reset password
  Future<bool> verifyOTPAndResetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    return await network(
        request: (request) => request.post(
              "/auth/verify-otp/",
              data: {
                "email": email,
                "otp": otp,
                "new_password": newPassword,
              },
            ),
        handleSuccess: (Response response) {
          return true;
        },
        handleFailure: (DioException dioError) {
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors.containsKey('error')) {
              throw Exception(errors['error']);
            }
          }
          throw Exception("Failed to verify OTP: ${dioError.message}");
        });
  }

  /// Update user profile
  Future<dynamic> updateProfile(
      {required String fullName,
      required String phoneNumber,
      required dateOfBirth}) async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.patch(
              "/profile/update/",
              data: {
                "full_name": fullName,
                "phone_number": phoneNumber,
                "date_of_birth": dateOfBirth.toString()
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          final userData = response.data;
          await storageSave("user", jsonEncode(userData));
          return userData;
        },
        handleFailure: (DioError dioError) {
          throw Exception("Failed to update profile: ${dioError.message}");
        });
  }

  /// Delete user account
  Future<bool> deleteAccount() async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete(
              "/account/delete/",
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Clean up local storage
          await Auth.logout();
          await backpackDelete('auth_token');
          await storageDelete("user");
          return true;
        },
        handleFailure: (DioError dioError) {
          throw Exception("Failed to delete account: ${dioError.message}");
        });
  }
}
