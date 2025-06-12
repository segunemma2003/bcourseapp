import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/networking/cache_invalidation_manager.dart';
import '../../utils/system_util.dart';
import '../models/course.dart';
import '../models/enrollment.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CourseApiService extends NyApiService {
  CourseApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  // Cache duration constants
  static const Duration CACHE_FEATURED_COURSES = Duration(hours: 12);
  static const Duration CACHE_TOP_COURSES = Duration(hours: 12);
  static const Duration CACHE_ALL_COURSES = Duration(hours: 6);
  static const Duration CACHE_COURSE_DETAILS = Duration(hours: 6);
  static const Duration CACHE_COURSE_CURRICULUM = Duration(hours: 4);
  static const Duration CACHE_COURSE_OBJECTIVES = Duration(hours: 12);
  static const Duration CACHE_COURSE_REQUIREMENTS = Duration(hours: 12);
  static const Duration CACHE_ENROLLED_COURSES = Duration(hours: 1);
  static const Duration CACHE_WISHLIST = Duration(hours: 1);
  static const Duration NETWORK_TIMEOUT = Duration(seconds: 30);

  /// Get featured courses with caching
  Future<List<dynamic>> getFeaturedCourses({bool refresh = false}) async {
    const cacheKey = 'featured_courses';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    final headers = await getAuthHeaders();

    return await network(
        request: (request) => request.get("/courses/featured/"),
        headers: headers,
        cacheKey: cacheKey,
        cacheDuration: CACHE_FEATURED_COURSES,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'featured courses');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch featured courses: ${dioError.message}");
        });
  }

  /// Get top courses with caching
  Future<List<dynamic>> getTopCourses({bool refresh = false}) async {
    const cacheKey = 'top_courses';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/courses/top/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_TOP_COURSES,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'top courses');
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch top courses: ${dioError.message}");
        });
  }

  /// Get all courses with intelligent caching based on filters
  Future<List<dynamic>> getAllCourses({
    int? categoryId,
    String? search,
    String? location,
    bool refresh = false,
  }) async {
    // Create unique cache key based on filters
    final cacheKey = _createCacheKey('courses', {
      if (categoryId != null) 'category': categoryId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (location != null && location.isNotEmpty) 'location': location,
    });

    if (refresh) {
      await cache().clear(cacheKey);
    }

    // Build query parameters
    Map<String, dynamic> queryParams = {};
    if (categoryId != null) queryParams['category'] = categoryId.toString();
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (location != null && location.isNotEmpty)
      queryParams['location'] = location;

    return await network(
        request: (request) =>
            request.get("/courses/", queryParameters: queryParams),
        cacheKey: cacheKey,
        cacheDuration: CACHE_ALL_COURSES,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'courses');
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch courses: ${dioError.message}");
        });
  }

  /// Get courses by category with caching
  Future<List<dynamic>> getCoursesByCategory(int categoryId,
      {bool refresh = false}) async {
    final cacheKey = 'courses_category_$categoryId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/courses/category/$categoryId/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_ALL_COURSES,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'category courses');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch courses for category: ${dioError.message}");
        });
  }

  /// Get course details with caching
  Future<dynamic> getCourseDetails(int courseId, {bool refresh = false}) async {
    final cacheKey = 'course_details_$courseId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_COURSE_DETAILS,
        handleSuccess: (Response response) => response.data,
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course details: ${dioError.message}");
        });
  }

  /// Get complete course details (including enrollment info) with caching
  Future<dynamic> getCompleteDetails(int courseId,
      {bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      // Fallback to regular course details if not authenticated
      return getCourseDetails(courseId, refresh: refresh);
    }

    final cacheKey = 'course_complete_details_$courseId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) =>
            request.get("/courses/$courseId/complete_details/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_COURSE_DETAILS,
        handleSuccess: (Response response) => response.data,
        handleFailure: (DioException dioError) {
          // Fallback to regular course details if API call fails
          return getCourseDetails(courseId, refresh: refresh);
        });
  }

  /// ✅ NEW: Get enrollments directly from enrollment API
  Future<List<dynamic>> getEnrollments({bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    const cacheKey = 'enrollments';

    if (refresh) {
      await cache().clear(cacheKey);
      NyLogger.info('Cleared enrollments cache due to refresh request');
    }

    final headers = await getAuthHeaders();

    return await network(
        request: (request) => request.get("/enrollments/"),
        headers: headers,
        cacheKey: cacheKey,
        cacheDuration: CACHE_ENROLLED_COURSES,
        handleSuccess: (Response response) {
          try {
            NyLogger.info(
                'Raw Enrollments API Response type: ${response.data.runtimeType}');
            NyLogger.info('Raw Enrollments API Response: ${response.data}');

            List<dynamic> enrollments;

            if (response.data is List) {
              enrollments = response.data as List<dynamic>;
              NyLogger.info(
                  '✅ Parsed direct array response with ${enrollments.length} enrollments');
            } else if (response.data is Map) {
              final responseMap = response.data as Map;
              if (responseMap.containsKey('results')) {
                enrollments = responseMap['results'] as List<dynamic>;
                NyLogger.info(
                    '✅ Parsed paginated response with ${enrollments.length} enrollments');
              } else {
                NyLogger.error('❌ Unexpected map response structure');
                NyLogger.error('Available keys: ${responseMap.keys.toList()}');
                throw Exception(
                    "Unexpected response format: Map without results");
              }
            } else {
              NyLogger.error(
                  '❌ Unexpected response type: ${response.data.runtimeType}');
              throw Exception(
                  "Unexpected response type: ${response.data.runtimeType}");
            }

            // Validate enrollment data structure
            for (int i = 0; i < enrollments.length; i++) {
              final enrollment = enrollments[i];
              if (enrollment is! Map) {
                NyLogger.error(
                    '⚠️ Enrollment at index $i is not a Map: ${enrollment.runtimeType}');
              } else {
                NyLogger.info(
                    '✅ Enrollment $i has keys: ${enrollment.keys.toList()}');

                // Validate course data within enrollment
                if (enrollment['course'] != null &&
                    enrollment['course'] is Map) {
                  final courseData = enrollment['course'] as Map;
                  NyLogger.info(
                      '   Course data keys: ${courseData.keys.toList()}');
                } else {
                  NyLogger.error('   ⚠️ Invalid course data in enrollment $i');
                }
              }
            }

            NyLogger.info(
                '✅ Successfully fetched ${enrollments.length} enrollments');
            return enrollments;
          } catch (parseError) {
            NyLogger.error('❌ Error parsing enrollments response: $parseError');
            NyLogger.error('Response data type: ${response.data.runtimeType}');
            NyLogger.error('Response data: ${response.data}');
            rethrow;
          }
        },
        handleFailure: (DioException dioError) {
          String errorMessage = "Failed to fetch enrollments";

          switch (dioError.type) {
            case DioExceptionType.connectionTimeout:
              errorMessage =
                  "Connection timeout - please check your internet connection";
              break;
            case DioExceptionType.receiveTimeout:
              errorMessage =
                  "Server response timeout - the request is taking too long";
              break;
            case DioExceptionType.sendTimeout:
              errorMessage = "Request timeout - please try again";
              break;
            case DioExceptionType.badResponse:
              if (dioError.response?.statusCode == 500) {
                errorMessage = "Server error - please try again later";
              } else if (dioError.response?.statusCode == 401) {
                errorMessage = "Authentication failed - please login again";
              } else if (dioError.response?.statusCode == 403) {
                errorMessage = "Access denied - insufficient permissions";
              } else {
                errorMessage =
                    "Server error (${dioError.response?.statusCode})";
              }
              break;
            case DioExceptionType.cancel:
              errorMessage = "Request was cancelled";
              break;
            case DioExceptionType.connectionError:
              errorMessage = "Connection error - please check your internet";
              break;
            default:
              errorMessage = "Network error occurred";
          }

          NyLogger.error(
              '❌ getEnrollments error: ${dioError.type} - ${dioError.message}');
          NyLogger.error('Response status: ${dioError.response?.statusCode}');
          NyLogger.error('Response data: ${dioError.response?.data}');

          throw Exception("$errorMessage: ${dioError.message}");
        });
  }

  /// ✅ NEW: Get enrollments as Enrollment objects
  Future<List<Enrollment>> getEnrollmentsAsObjects(
      {bool refresh = false}) async {
    try {
      final enrollmentsData = await getEnrollments(refresh: refresh);
      return enrollmentsData
          .map((enrollmentData) => Enrollment.fromJson(enrollmentData))
          .toList();
    } catch (e) {
      NyLogger.error('Error getting enrollments as objects: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Get enrollments with fallback to cached data
  Future<List<dynamic>> getEnrollmentsWithFallback(
      {bool refresh = false}) async {
    try {
      return await getEnrollments(refresh: refresh);
    } catch (e) {
      NyLogger.error('Primary enrollments fetch failed: $e');

      try {
        final cachedData = await cache().get('enrollments');
        if (cachedData != null && cachedData is List) {
          NyLogger.info('Using cached enrollments data as fallback');
          return cachedData;
        }
      } catch (cacheError) {
        NyLogger.error('Cache fallback failed: $cacheError');
      }

      NyLogger.error('Returning empty enrollments list as last resort');
      return [];
    }
  }

  /// ✅ DEPRECATED: Keep for backward compatibility, but now uses enrollment API
  @Deprecated(
      'Use getEnrollments() instead - this method now redirects to the enrollment API')
  Future<List<dynamic>> getEnrolledCourses({bool refresh = false}) async {
    NyLogger.info(
        '⚠️ getEnrolledCourses() is deprecated, redirecting to getEnrollments()');
    return await getEnrollments(refresh: refresh);
  }

  /// ✅ DEPRECATED: Keep for backward compatibility
  @Deprecated('Use getEnrollmentsWithFallback() instead')
  Future<List<dynamic>> getEnrolledCoursesWithFallback(
      {bool refresh = false}) async {
    NyLogger.info(
        '⚠️ getEnrolledCoursesWithFallback() is deprecated, redirecting to getEnrollmentsWithFallback()');
    return await getEnrollmentsWithFallback(refresh: refresh);
  }

  Future<Course> getCourseWithEnrollmentDetails(int courseId,
      {bool refresh = false}) async {
    try {
      final courseData = await getCourseDetails(courseId, refresh: refresh);
      return Course.fromJson(courseData);
    } catch (e) {
      NyLogger.error('Error getting course with enrollment details: $e');
      rethrow;
    }
  }

  Future<List<Course>> getAllCoursesAsObjects({
    int? categoryId,
    String? search,
    String? location,
    bool refresh = false,
  }) async {
    try {
      final coursesData = await getAllCourses(
        categoryId: categoryId,
        search: search,
        location: location,
        refresh: refresh,
      );
      return coursesData
          .map((courseData) => Course.fromJson(courseData))
          .toList();
    } catch (e) {
      NyLogger.error('Error getting courses as objects: $e');
      rethrow;
    }
  }

  Future<void> preloadEnrollmentsInBackground() async {
    try {
      final authToken = await backpackRead('auth_token');
      if (authToken == null) return;

      // Check if we already have recent cached data
      final cachedData = await cache().get('enrollments');
      if (cachedData != null) {
        NyLogger.info(
            'Enrollments already cached, skipping background preload');
        return;
      }

      // Load in background without waiting
      Future.microtask(() async {
        try {
          await getEnrollments();
          NyLogger.info('Background preload of enrollments completed');
        } catch (e) {
          NyLogger.error('Background preload of enrollments failed: $e');
        }
      });
    } catch (e) {
      NyLogger.error('Error starting background enrollments preload: $e');
    }
  }

  Future<Map<String, dynamic>> createPaymentOrder({
    required int courseId,
    required String planType,
    int? paymentCardId,
  }) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    Map<String, dynamic> data = {
      "course_id": courseId,
      "plan_type": planType,
    };

    if (paymentCardId != null) {
      data["payment_card_id"] = paymentCardId;
    }

    try {
      return await network(
        request: (request) =>
            request.post("/payments/create-order/", data: data),
        headers: {
          "Authorization": "Token $authToken",
          "Content-Type": "application/json",
        },
        handleSuccess: (Response response) {
          NyLogger.info('✅ Payment order created successfully');
          NyLogger.debug('Order response: ${response.data}');
          return response.data;
        },
        handleFailure: (DioException dioError) {
          String errorMessage = "Failed to create payment order";

          if (dioError.response?.data != null) {
            try {
              final errorData = dioError.response!.data;
              if (errorData is Map<String, dynamic>) {
                if (errorData.containsKey('error')) {
                  errorMessage = errorData['error'].toString();
                } else if (errorData.containsKey('message')) {
                  errorMessage = errorData['message'].toString();
                }
              }
            } catch (e) {
              NyLogger.error('Error parsing create order error response: $e');
            }
          }

          NyLogger.error('❌ Create order failed: $errorMessage');
          throw Exception("$errorMessage: ${dioError.message}");
        },
      );
    } catch (e) {
      NyLogger.error('❌ Create payment order error: $e');
      rethrow;
    }
  }

  /// Get user's wishlist with short caching
  Future<List<dynamic>> getWishlist({bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    const cacheKey = 'wishlist';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/wishlist/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_WISHLIST,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'wishlist');
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch wishlist: ${dioError.message}");
        });
  }

  /// Get course curriculum with caching
  Future<List<dynamic>> getCourseCurriculum(int courseId,
      {bool refresh = false}) async {
    final cacheKey = 'course_curriculum_$courseId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    final authToken = await backpackRead('auth_token');
    Map<String, String> headers = {};
    if (authToken != null) {
      headers["Authorization"] = "Token $authToken";
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/curriculum/"),
        headers: headers,
        cacheKey: cacheKey,
        cacheDuration: CACHE_COURSE_CURRICULUM,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'curriculum');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course curriculum: ${dioError.message}");
        });
  }

  /// Get course objectives with caching
  Future<List<dynamic>> getCourseObjectives(int courseId,
      {bool refresh = false}) async {
    final cacheKey = 'course_objectives_$courseId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/objectives/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_COURSE_OBJECTIVES,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'objectives');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course objectives: ${dioError.message}");
        });
  }

  /// Get course requirements with caching
  Future<List<dynamic>> getCourseRequirements(int courseId,
      {bool refresh = false}) async {
    final cacheKey = 'course_requirements_$courseId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/requirements/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_COURSE_REQUIREMENTS,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'requirements');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course requirements: ${dioError.message}");
        });
  }

  /// Purchase course (invalidates relevant caches)
  Future<dynamic> purchaseCourse({
    required int courseId,
    required String planType,
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
    int? paymentCardId,
  }) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    Map<String, dynamic> data = {
      "course_id": courseId,
      "plan_type": planType,
      "razorpay_payment_id": razorpayPaymentId,
      "razorpay_order_id": razorpayOrderId,
      "razorpay_signature": razorpaySignature,
    };

    if (paymentCardId != null) {
      data["payment_card_id"] = paymentCardId;
    }

    return await network(
        request: (request) =>
            request.post("/payments/purchase-course/", data: data),
        headers: {
          "Authorization": "Token $authToken",
          "Content-Type": "application/json",
        },
        handleSuccess: (Response response) async {
          // Invalidate relevant caches after successful purchase
          await _invalidatePostPurchaseCaches(courseId);
          await CacheInvalidationManager.onCoursePurchase(courseId);
          NyLogger.info('Course purchased successfully: $courseId');
          return response.data;
        },
        handleFailure: (DioException dioError) {
          String errorMessage = "Failed to purchase course";

          if (dioError.response?.data != null) {
            try {
              final errorData = dioError.response!.data;
              if (errorData is Map<String, dynamic>) {
                if (errorData.containsKey('error')) {
                  errorMessage = errorData['error'].toString();
                } else if (errorData.containsKey('message')) {
                  errorMessage = errorData['message'].toString();
                } else if (errorData.containsKey('details')) {
                  errorMessage = errorData['details'].toString();
                }
              }
            } catch (e) {
              NyLogger.error('Error parsing purchase error response: $e');
            }
          }

          throw Exception("$errorMessage: ${dioError.message}");
        });
  }

  /// Add course to wishlist (invalidates wishlist cache)
  Future<dynamic> addToWishlist(int courseId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) =>
            request.post("/wishlist/", data: {"course": courseId}),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate wishlist cache
          await cache().clear('wishlist');
          await CacheInvalidationManager.onWishlistChange();

          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to add course to wishlist: ${dioError.message}");
        });
  }

  /// Remove course from wishlist (invalidates wishlist cache)
  Future<bool> removeFromWishlist(int wishlistItemId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/wishlist/$wishlistItemId/"),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate wishlist cache
          await cache().clear('wishlist');
          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to remove course from wishlist: ${dioError.message}");
        });
  }

  /// Enroll in course (invalidates relevant caches)
  Future<dynamic> enrollInCourse(int courseId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) =>
            request.post("/enrollments/", data: {"course": courseId}),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate relevant caches after enrollment
          await _invalidatePostEnrollmentCaches(courseId);
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to enroll in course: ${dioError.message}");
        });
  }

  /// ✅ NEW: Get specific enrollment details by enrollment ID
  Future<dynamic> getEnrollmentDetails(int enrollmentId,
      {bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    final cacheKey = 'enrollment_details_$enrollmentId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/enrollments/$enrollmentId/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_COURSE_DETAILS,
        handleSuccess: (Response response) {
          NyLogger.info(
              '✅ Successfully fetched enrollment details for ID: $enrollmentId');
          return response.data;
        },
        handleFailure: (DioException dioError) {
          NyLogger.error(
              '❌ Failed to fetch enrollment details: ${dioError.message}');
          throw Exception(
              "Failed to fetch enrollment details: ${dioError.message}");
        });
  }

  /// ✅ NEW: Get enrollment details as EnrollmentDetails object
  Future<EnrollmentDetails> getEnrollmentDetailsAsObject(int enrollmentId,
      {bool refresh = false}) async {
    try {
      final enrollmentData =
          await getEnrollmentDetails(enrollmentId, refresh: refresh);
      return EnrollmentDetails.fromJson(enrollmentData);
    } catch (e) {
      NyLogger.error('Error getting enrollment details as object: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Get specific enrollment by course ID (searches through enrollments list)
  Future<Enrollment?> getEnrollmentForCourse(int courseId) async {
    try {
      final authToken = await backpackRead('auth_token');
      if (authToken == null) {
        return null;
      }

      List<dynamic> enrollmentsData = await getEnrollments();

      for (var enrollmentData in enrollmentsData) {
        if (enrollmentData['course'] != null &&
            enrollmentData['course']['id'].toString() == courseId.toString()) {
          return Enrollment.fromJson(enrollmentData);
        }
      }

      return null;
    } catch (e) {
      NyLogger.error('Error getting enrollment for course $courseId: $e');
      return null;
    }
  }

  /// ✅ NEW: Check if user has valid enrollment for a course
  Future<bool> hasValidEnrollmentForCourse(int courseId) async {
    try {
      final enrollment = await getEnrollmentForCourse(courseId);
      return enrollment?.isValid ?? false;
    } catch (e) {
      NyLogger.error(
          'Error checking enrollment validity for course $courseId: $e');
      return false;
    }
  }

  Future<void> preloadEssentialDataWithEnrollmentStatus() async {
    try {
      final isAuthenticated = await backpackRead('auth_token') != null;

      await Future.wait([
        getFeaturedCourses().catchError((e) {
          NyLogger.error('Failed to preload featured courses: $e');
          return <dynamic>[];
        }),
        getTopCourses().catchError((e) {
          NyLogger.error('Failed to preload top courses: $e');
          return <dynamic>[];
        }),
        getAllCourses().catchError((e) {
          NyLogger.error('Failed to preload all courses: $e');
          return <dynamic>[];
        }),
        preloadEnrollmentsInBackground().catchError((e) {
          NyLogger.error('Failed to preload enrollments: $e');
          return <dynamic>[];
        }),
      ]);

      if (isAuthenticated) {
        await Future.wait([
          getEnrollments().catchError((e) {
            NyLogger.error('Failed to preload enrollments: $e');
            return <dynamic>[];
          }),
          getWishlist().catchError((e) {
            NyLogger.error('Failed to preload wishlist: $e');
            return <dynamic>[];
          }),
        ]);
      }

      NyLogger.info('Course data preloading completed with enrollment status');
    } catch (e) {
      NyLogger.error('Failed to preload course data: ${e.toString()}');
    }
  }

  /// Invalidate enrollment-specific caches
  Future<void> invalidateEnrollmentCaches() async {
    final cacheKeysToInvalidate = [
      'enrollments',
      'enrolled_courses', // Keep for backward compatibility
    ];

    await Future.wait(cacheKeysToInvalidate.map((key) => cache().clear(key)));
    NyLogger.info('Invalidated enrollment caches');
  }

  /// ✅ DEPRECATED: Use Enrollment.isValid property instead
  @Deprecated('Use Enrollment.isValid property instead')
  Future<bool> checkEnrollmentValidity(int courseId) async {
    try {
      final enrollment = await getEnrollmentForCourse(courseId);
      return enrollment?.isValid ?? false;
    } catch (e) {
      NyLogger.error('Error checking enrollment validity: $e');
      return false;
    }
  }

  /// Preload essential data with optimized parallel loading
  Future<void> preloadEssentialData() async {
    try {
      // Load courses data in parallel
      await Future.wait([
        getFeaturedCourses().catchError((e) {
          NyLogger.error('Failed to preload featured courses: $e');
          return <dynamic>[];
        }),
        getTopCourses().catchError((e) {
          NyLogger.error('Failed to preload top courses: $e');
          return <dynamic>[];
        }),
        getAllCourses().catchError((e) {
          NyLogger.error('Failed to preload all courses: $e');
          return <dynamic>[];
        }),
      ]);

      // Check if user is authenticated for user-specific data
      final isAuthenticated = await backpackRead('auth_token') != null;

      if (isAuthenticated) {
        await Future.wait([
          getEnrollments().catchError((e) {
            NyLogger.error('Failed to preload enrollments: $e');
            return <dynamic>[];
          }),
          getWishlist().catchError((e) {
            NyLogger.error('Failed to preload wishlist: $e');
            return <dynamic>[];
          }),
        ]);
      }

      NyLogger.info('Course data preloading completed');
    } catch (e) {
      NyLogger.error('Failed to preload course data: ${e.toString()}');
    }
  }

  /// Invalidate all course-related caches (call after major updates)
  Future<void> invalidateAllCaches() async {
    final cacheKeysToInvalidate = [
      'featured_courses',
      'top_courses',
      'enrollments',
      'enrolled_courses', // Keep for backward compatibility
      'wishlist',
    ];

    await Future.wait(cacheKeysToInvalidate.map((key) => cache().clear(key)));
    NyLogger.info('Invalidated all course-related caches');
  }

  // Helper methods

  /// Parse different response structures into consistent List format
  List<dynamic> _parseCoursesResponse(dynamic responseData, String context) {
    try {
      if (responseData is List) {
        return responseData;
      } else if (responseData is Map) {
        // Check common keys for list data
        final possibleKeys = [
          'data',
          'results',
          'items',
          context.toLowerCase()
        ];

        for (final key in possibleKeys) {
          if (responseData.containsKey(key) && responseData[key] is List) {
            return responseData[key];
          }
        }

        return [responseData];
      } else if (responseData is String) {
        try {
          final parsed = jsonDecode(responseData);
          if (parsed is List) {
            return parsed;
          }
          return [parsed];
        } catch (e) {
          return [
            {"text": responseData}
          ];
        }
      } else if (responseData != null) {
        return [
          {"value": responseData}
        ];
      }

      return [];
    } catch (e) {
      NyLogger.error('Error parsing $context response: $e');
      return [];
    }
  }

  /// Create cache key with parameters
  String _createCacheKey(String base, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) {
      return base;
    }

    final sortedKeys = params.keys.toList()..sort();
    final paramString =
        sortedKeys.map((key) => '${key}_${params[key]}').join('_');

    return '${base}_$paramString';
  }

  /// Invalidate caches after purchase
  Future<void> _invalidatePostPurchaseCaches(int courseId) async {
    // Clear ALL course-related caches to ensure fresh data everywhere
    await Future.wait([
      // User-specific caches
      cache().clear('enrollments'),
      cache().clear('enrolled_courses'), // Backward compatibility
      cache().clear('wishlist'),

      // Course-specific caches
      cache().clear('course_details_$courseId'),
      cache().clear('course_complete_details_$courseId'),
      cache().clear('course_curriculum_$courseId'),

      // General course listing caches - CRITICAL for SearchTab updates
      cache().clear('featured_courses'),
      cache().clear('top_courses'),
      cache().clear('courses'), // Base courses cache

      // Category-specific caches (we need to clear all categories)
      _clearAllCategoryCaches(),
    ]);

    // Preload fresh enrollment data in background
    Future.microtask(() async {
      try {
        await getEnrollmentsWithFallback(refresh: true);
        NyLogger.info('Preloaded fresh enrollments after purchase');
      } catch (e) {
        NyLogger.error('Failed to preload enrollments after purchase: $e');
      }
    });

    NyLogger.info(
        'Invalidated all course caches after purchase for course $courseId');
  }

  Future<bool> _isNetworkAvailable() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// ✅ NEW: Get enrollments with network check
  Future<List<dynamic>> getEnrollmentsWithNetworkCheck(
      {bool refresh = false}) async {
    // Check network first
    final hasNetwork = await _isNetworkAvailable();
    if (!hasNetwork) {
      NyLogger.error('No network available, using cached enrollments');
      final cachedData = await cache().get('enrollments');
      if (cachedData != null && cachedData is List) {
        return cachedData;
      }
      throw Exception("No internet connection and no cached data available");
    }

    return await getEnrollmentsWithFallback(refresh: refresh);
  }

  Future<void> _clearAllCategoryCaches() async {
    try {
      // Get all possible category IDs and clear their caches
      // This is a brute force approach but ensures consistency
      for (int categoryId = 1; categoryId <= 20; categoryId++) {
        await cache().clear('courses_category_$categoryId');
      }
    } catch (e) {
      NyLogger.error('Error clearing category caches: $e');
    }
  }

  /// Invalidate caches after enrollment
  Future<void> _invalidatePostEnrollmentCaches(int courseId) async {
    await Future.wait([
      cache().clear('enrollments'),
      cache().clear('enrolled_courses'), // Backward compatibility
      cache().clear('course_details_$courseId'),
      cache().clear('course_complete_details_$courseId'),
    ]);
    NyLogger.info('Invalidated post-enrollment caches for course $courseId');
  }

  /// ✅ NEW: Helper method to get authentication headers
  Future<Map<String, String>> getAuthHeaders() async {
    final authToken = await backpackRead('auth_token');
    if (authToken != null) {
      return {"Authorization": "Token $authToken"};
    }
    return {};
  }
}
