import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/utils/system_util.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';

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

  Future<dynamic> getProfilePicture() async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.get("/profile/picture/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to get profile picture: ${dioError.message}");
        });
  }

  Future<dynamic> uploadProfilePicture(File imageFile) async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Get file extension and prepare FormData
    String fileName = imageFile.path.split('/').last;
    String extension = fileName.split('.').last.toLowerCase();

    // Create form data for multipart upload
    FormData formData = FormData.fromMap({
      "profile_picture": await MultipartFile.fromFile(
        imageFile.path,
        filename: fileName,
        contentType: MediaType('image', extension),
      ),
    });

    return await network(
        request: (request) => request.patch(
              "/profile/picture/upload/",
              data: formData,
            ),
        headers: {
          "Authorization": "Token ${authToken}",
          "Content-Type": "multipart/form-data",
        },
        handleSuccess: (Response response) async {
          // Update user data with new profile picture
          var userData = await Auth.data();
          if (userData != null) {
            userData['profile_picture_url'] =
                response.data['profile_picture_url'];
            await Auth.authenticate(data: userData);
            await storageSave("user", userData);
          }

          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to upload profile picture: ${dioError.message}");
        });
  }

  /// Delete profile picture
  Future<bool> deleteProfilePicture() async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/profile/picture/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Update user data after picture deletion
          var userData = await Auth.data();
          if (userData != null) {
            userData['profile_picture_url'] = null;
            await Auth.authenticate(data: userData);
            await storageSave("user", userData);
          }

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to delete profile picture: ${dioError.message}");
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

  Future<dynamic> requestPasswordReset({required String email}) async {
    return await network(
        request: (request) => request.post(
              "/auth/forgot-password/",
              data: {
                "email": email,
              },
            ),
        handleSuccess: (Response response) async {
          await storageSave("forgot_email", email);
          return response
              .data; // Returns {message: string, otp_expires_in: string}
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

  /// Verify OTP - UPDATED (separate endpoint)
  Future<dynamic> verifyOTP({
    required String email,
    required String otp,
  }) async {
    return await network(
        request: (request) => request.post(
              "/auth/verify-otp/",
              data: {
                "email": email,
                "otp": otp,
              },
            ),
        handleSuccess: (Response response) async {
          // Store verification success in storage for next step
          await storageSave("otp_verified", true);
          return response.data; // Returns {message: string, otp_verified: bool}
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

  /// Reset password with verified OTP - UPDATED
  Future<dynamic> resetPasswordWithVerifiedOTP({
    required String email,
    required String otp,
    required String newPassword,
    required String confirmPassword,
  }) async {
    return await network(
        request: (request) => request.post(
              "/auth/reset-password/",
              data: {
                "email": email,
                "otp": otp,
                "new_password": newPassword,
                "confirm_password": confirmPassword,
              },
            ),
        handleSuccess: (Response response) async {
          // Clear temporary storage after successful reset
          await storageDelete("forgot_email");
          await storageDelete("otp_verified");
          await storageDelete("temp_otp");
          return response
              .data; // Returns {message: string, password_reset: bool}
        },
        handleFailure: (DioException dioError) {
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors.containsKey('error')) {
              throw Exception(errors['error']);
            }
          }
          throw Exception("Failed to reset password: ${dioError.message}");
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
