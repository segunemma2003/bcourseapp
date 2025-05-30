import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/networking/cache_invalidation_manager.dart';
import 'package:flutter_app/app/networking/token_helper.dart';
import 'package:flutter_app/utils/system_util.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../providers/firebase_service_provider.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'dart:io';
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
            await TokenSyncHelper.saveAuthToken(responseData['key']);
            if (responseData['user'] != null) {
              await storageSave("user", responseData['user']);
              await Auth.authenticate(data: responseData['user']);

              try {
                // Get FCM token and register device - make non-blocking
                String? fcmToken = await backpackRead('fcm_token');
                if (fcmToken == null) {
                  fcmToken = await FirebaseMessaging.instance.getToken();
                  if (fcmToken != null) {
                    await backpackSave('fcm_token', fcmToken);
                  }
                }

                if (fcmToken != null) {
                  // Make device registration non-blocking
                  registerDeviceWithBackend(fcmToken).catchError((e) {
                    NyLogger.error(
                        'Device registration error (non-blocking): $e');
                  });
                }

                // Make topic subscription non-blocking
                FirebaseServiceProvider.subscribeToUserTopics().catchError((e) {
                  NyLogger.error('Topic subscription error (non-blocking): $e');
                });
                await CacheInvalidationManager.onUserLogin();
                // Make data preloading non-blocking
                preloadEssentialData().catchError((e) {
                  NyLogger.error('Data preloading error (non-blocking): $e');
                });
              } catch (e) {
                // Log but don't block registration flow for notification setup errors
                NyLogger.error('Non-critical error during registration: $e');
              }
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
          if (responseData['key'] != null) {
            await TokenSyncHelper.saveAuthToken(responseData['key']);
            if (responseData['user'] != null) {
              await storageSave("user", responseData['user']);
              await Auth.authenticate(data: responseData['user']);

              try {
                // Get FCM token and register device
                String? fcmToken = await backpackRead('fcm_token');
                if (fcmToken == null) {
                  fcmToken = await FirebaseMessaging.instance.getToken();
                  if (fcmToken != null) {
                    await backpackSave('fcm_token', fcmToken);
                  }
                }

                if (fcmToken != null) {
                  // Make device registration non-blocking
                  registerDeviceWithBackend(fcmToken).catchError((e) {
                    NyLogger.error(
                        'Device registration error (non-blocking): $e');
                  });
                }

                // Make topic subscription non-blocking
                FirebaseServiceProvider.subscribeToUserTopics().catchError((e) {
                  NyLogger.error('Topic subscription error (non-blocking): $e');
                });
                await CacheInvalidationManager.onUserLogin();
                // Make data preloading non-blocking
                preloadEssentialData().catchError((e) {
                  NyLogger.error('Data preloading error (non-blocking): $e');
                });
              } catch (e) {
                // Log but don't block login flow for notification setup errors
                NyLogger.error('Non-critical error during login: $e');
              }
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

// Modified Google login function in UserApiService class
  Future<dynamic> loginWithGoogleFirebase() async {
    try {
      // Initialize the GoogleSignIn instance
      final GoogleSignIn googleSignIn = GoogleSignIn();

      print("i am here");
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception("Google sign-in was canceled");
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Get Firebase ID token
      String? firebaseToken = await userCredential.user?.getIdToken();

      if (firebaseToken == null) {
        throw Exception("Failed to obtain Firebase token");
      }

      // Get FCM token for push notifications
      String? fcmToken = await backpackRead('fcm_token');
      if (fcmToken == null) {
        fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await backpackSave('fcm_token', fcmToken);
        }
      }

      // Send the Firebase token to your Django backend
      return await network(
          request: (request) => request.post(
                "/auth/firebase-google/",
                data: {
                  "id_token": firebaseToken,
                  "fcm_token": fcmToken,
                },
              ),
          handleSuccess: (Response response) async {
            // Store user token and data
            final responseData = response.data;
            if (responseData['key'] != null) {
              await TokenSyncHelper.saveAuthToken(responseData['key']);
              if (responseData['user'] != null) {
                await storageSave("user", responseData['user']);
                await Auth.authenticate(data: responseData['user']);

                try {
                  // Make device registration non-blocking
                  if (fcmToken != null) {
                    registerDeviceWithBackend(fcmToken).catchError((e) {
                      NyLogger.error(
                          'Device registration error (non-blocking): $e');
                    });
                  } else {
                    // Try one more time to get FCM token
                    String? newToken =
                        await FirebaseMessaging.instance.getToken();
                    if (newToken != null) {
                      await backpackSave('fcm_token', newToken);
                      registerDeviceWithBackend(newToken).catchError((e) {
                        NyLogger.error(
                            'Device registration error (non-blocking): $e');
                      });
                      await CacheInvalidationManager.onUserLogin();
                      // Make data preloading non-blocking
                      preloadEssentialData().catchError((e) {
                        NyLogger.error(
                            'Data preloading error (non-blocking): $e');
                      });
                    }
                  }

                  // Make topic subscription non-blocking
                  FirebaseServiceProvider.subscribeToUserTopics()
                      .catchError((e) {
                    NyLogger.error(
                        'Topic subscription error (non-blocking): $e');
                  });

                  // Make data preloading non-blocking
                  preloadEssentialData().catchError((e) {
                    NyLogger.error('Data preloading error (non-blocking): $e');
                  });
                } catch (e) {
                  // Log but don't block login flow for notification setup errors
                  NyLogger.error('Non-critical error during Google login: $e');
                }
              }
            }
            return responseData;
          },
          handleFailure: (DioException dioError) {
            // Handle API error response
            if (dioError.response?.data != null) {
              final errors = dioError.response!.data;
              String errorMessage = "Google sign-in failed";

              if (errors.containsKey('error')) {
                errorMessage = errors['error'];
              } else if (errors.containsKey('non_field_errors')) {
                errorMessage = errors['non_field_errors'][0];
              } else if (errors.containsKey('detail')) {
                errorMessage = errors['detail'];
              }

              throw Exception(errorMessage);
            }
            throw Exception("Google sign-in failed: ${dioError.message}");
          });
    } catch (e) {
      // Clean up Firebase auth state if there was an error
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      // Clean up Google Sign-In state if there was an error
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      if (e is DioException) {
        throw Exception("Google sign-in failed: ${e.message}");
      }
      throw Exception(e.toString());
    }
  }

// Make device registration function more resilient
  Future<void> registerDeviceWithBackend(String token) async {
    try {
      // Get auth token
      final authToken = await backpackRead('auth_token');
      if (authToken == null) return;

      // Get unique device ID
      String deviceId = await _getDeviceId();

      // Make API call to register device
      await network(
        request: (request) => request.post(
          "/devices/",
          data: {
            "registration_id": token,
            "device_id": deviceId,
            "active": true
          },
        ),
        headers: {
          "Authorization": "Token $authToken",
        },
        handleSuccess: (response) {
          NyLogger.info(
              'Device registered successfully for push notifications');
        },
        handleFailure: (error) {
          // Just log the error but don't throw
          NyLogger.error('Failed to register device: ${error.message}');
        },
      );
    } catch (e) {
      // Just log the error but don't throw
      NyLogger.error('Error registering device: $e');
    }
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

  // Register device for push notifications

  /// Log out user
  /// Log out user
  Future<bool> logout() async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      return true; // Already logged out
    }

    // Unsubscribe from FCM topics before logging out
    await FirebaseServiceProvider.unsubscribeFromAllTopics();

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

          // Sign out from Google if needed
          if (_googleSignIn.currentUser != null) {
            await _googleSignIn.signOut();
          }

          // Sign out from Firebase if needed
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}

          await CacheInvalidationManager.onUserLogout();
          return true;
        },
        handleFailure: (DioException dioError) async {
          // Still clear local data on error
          await backpackDelete('auth_token');
          await storageDelete("user");

          // Also sign out from Google and Firebase on error
          if (_googleSignIn.currentUser != null) {
            await _googleSignIn.signOut();
          }

          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}

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
          await storageSave("user", userData);

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
          await CacheInvalidationManager.onProfileUpdate();
          await storageSave("user", userData);
          return userData;
        },
        handleFailure: (DioError dioError) {
          throw Exception("Failed to update profile: ${dioError.message}");
        });
  }

  Future<bool> recoverAuthenticationState() async {
    try {
      // Check if user is authenticated in framework but token is missing
      bool isAuthenticated = await Auth.isAuthenticated();
      final authToken = await backpackRead('auth_token');
      final userData = await storageRead("user");

      if (isAuthenticated && authToken == null && userData != null) {
        NyLogger.info('Attempting to recover missing auth token...');

        // Check if Auth.data() contains the token
        final authData = await Auth.data();
        if (authData != null) {
          // Look for token in various possible keys
          String? recoveredToken;

          if (authData.containsKey('auth_token')) {
            recoveredToken = authData['auth_token'];
          } else if (authData.containsKey('token')) {
            recoveredToken = authData['token'];
          } else if (authData.containsKey('key')) {
            recoveredToken = authData['key'];
          }

          if (recoveredToken != null) {
            await backpackSave('auth_token', recoveredToken);
            NyLogger.info('Successfully recovered auth token');
            return true;
          }
        }

        // If we can't recover the token, try to get a fresh one
        // by calling getCurrentUser() which might work with session cookies
        try {
          final currentUser = await getCurrentUser();
          if (currentUser != null) {
            NyLogger.info('Successfully refreshed user session');
            return true;
          }
        } catch (e) {
          NyLogger.error('Failed to refresh user session: $e');
        }
      }

      return false;
    } catch (e) {
      NyLogger.error('Error during auth state recovery: $e');
      return false;
    }
  }

  /// Check if authentication state is consistent
  Future<bool> validateAuthenticationState() async {
    try {
      final isAuthenticated = await Auth.isAuthenticated();
      final authToken = await backpackRead('auth_token');
      final userData = await storageRead("user");

      // All should be present and consistent
      if (isAuthenticated && authToken != null && userData != null) {
        return true;
      }

      // Try to recover if possible
      if (isAuthenticated && authToken == null) {
        return await recoverAuthenticationState();
      }

      return false;
    } catch (e) {
      NyLogger.error('Error validating auth state: $e');
      return false;
    }
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

  Future<String> _getDeviceId() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id; // Use Android device ID
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ??
            'unknown_ios_device'; // Use iOS vendor identifier
      }

      return 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      NyLogger.error('Error getting device ID: $e');
      return 'error_device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
