import 'dart:convert';
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

  Future<Course> getCourseWithEnrollmentDetails(int courseId,
      {bool refresh = false}) async {
    try {
      //  Use your existing getCourseDetails method - it already includes enrollment status when authenticated
      final courseData = await getCourseDetails(courseId, refresh: refresh);
      return Course.fromJson(courseData);
    } catch (e) {
      NyLogger.error('Error getting course with enrollment details: $e');
      rethrow;
    }
  }

  Future<List<Course>> getEnrolledCoursesAsObjects(
      {bool refresh = false}) async {
    try {
      //  Use your existing getEnrolledCourses method
      final coursesData = await getEnrolledCourses(refresh: refresh);
      return coursesData
          .map((courseData) => Course.fromJson(courseData))
          .toList();
    } catch (e) {
      NyLogger.error('Error getting enrolled courses as objects: $e');
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
      // Use your existing getAllCourses method - it already includes enrollment status when authenticated
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

  /// Get user's enrolled courses with short caching
  Future<List<dynamic>> getEnrolledCourses({bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    const cacheKey = 'enrolled_courses';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/enrollments/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_ENROLLED_COURSES,
        handleSuccess: (Response response) {
          return _parseCoursesResponse(response.data, 'enrolled courses');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch enrolled courses: ${dioError.message}");
        });
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

  /// Get enrollment for specific course (with caching)
  Future<Map<String, dynamic>?> getEnrollmentForCourse(int courseId) async {
    try {
      final authToken = await backpackRead('auth_token');
      if (authToken == null) {
        return null;
      }

      List<dynamic> enrollments = await getEnrolledCourses();

      for (var enrollment in enrollments) {
        if (enrollment['course'] != null &&
            enrollment['course']['id'].toString() == courseId.toString()) {
          return enrollment;
        }
      }

      return null;
    } catch (e) {
      NyLogger.error('Error getting enrollment for course $courseId: $e');
      return null;
    }
  }

  Future<void> preloadEssentialDataWithEnrollmentStatus() async {
    try {
      final isAuthenticated = await backpackRead('auth_token') != null;

      // ✅ Use existing methods - they already include enrollment status when authenticated
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

      if (isAuthenticated) {
        await Future.wait([
          getEnrolledCourses().catchError((e) {
            NyLogger.error('Failed to preload enrolled courses: $e');
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
      'enrolled_courses',
      'enrolled_courses_with_status',
    ];

    await Future.wait(cacheKeysToInvalidate.map((key) => cache().clear(key)));

    // Also invalidate any course complete details caches
    // Note: You might want to track specific course IDs and clear their complete details
  }

  /// Check enrollment validity
  @Deprecated('Use Course.hasValidSubscription property instead')
  Future<bool> checkEnrollmentValidity(int courseId) async {
    try {
      // Try to get course with enrollment details first
      final course = await getCourseWithEnrollmentDetails(courseId);
      return course.hasValidSubscription;
    } catch (e) {
      NyLogger.error('Error checking enrollment validity: $e');

      // Fallback to original method
      try {
        dynamic enrollmentData = await getEnrollmentForCourse(courseId);

        if (enrollmentData == null) {
          return false;
        }

        Enrollment enrollment = Enrollment.fromJson(enrollmentData);

        if (!enrollment.isActive) {
          return false;
        }

        if (enrollment.planType == Enrollment.PLAN_TYPE_LIFETIME) {
          return true;
        }

        if (enrollment.expiryDate == null) {
          return false;
        }

        DateTime expiryDate = DateTime.parse(enrollment.expiryDate!);
        return expiryDate.isAfter(DateTime.now());
      } catch (e) {
        NyLogger.error('Error in fallback enrollment check: $e');
        return false;
      }
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
          getEnrolledCourses().catchError((e) {
            NyLogger.error('Failed to preload enrolled courses: $e');
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
      'enrolled_courses',
      'wishlist',
    ];

    await Future.wait(cacheKeysToInvalidate.map((key) => cache().clear(key)));

    // Also clear any course-specific caches
    // Note: In a real implementation, you might want to track which specific course caches exist
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
    await Future.wait([
      cache().clear('enrolled_courses'),
      cache().clear('course_details_$courseId'),
      cache().clear('course_complete_details_$courseId'),
      cache().clear('wishlist'),
    ]);
  }

  /// Invalidate caches after enrollment
  Future<void> _invalidatePostEnrollmentCaches(int courseId) async {
    await Future.wait([
      cache().clear('enrolled_courses'),
      cache().clear('course_details_$courseId'),
      cache().clear('course_complete_details_$courseId'),
    ]);
  }
}
