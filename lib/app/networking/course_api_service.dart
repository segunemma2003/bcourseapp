import 'dart:convert';

import 'package:flutter/material.dart';
import '../../utils/system_util.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CourseApiService extends NyApiService {
  CourseApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  /// Get featured courses
  /// Get featured courses
  Future<List<dynamic>> getFeaturedCourses({bool refresh = false}) async {
    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead('featured_courses');
      if (cached != null) {
        // Ensure cached data is a List
        if (cached is List) {
          return cached;
        } else if (cached is String) {
          try {
            final parsedData = jsonDecode(cached);
            if (parsedData is List) {
              return parsedData;
            }
          } catch (e) {
            NyLogger.error('Error parsing cached featured courses data: $e');
          }
        }
        // If we reach here, cached data is invalid, so fetch fresh data
      }
    }

    final headers = await getAuthHeaders();

    return await network(
        request: (request) => request.get("/courses/featured/"),
        headers: headers,
        handleSuccess: (Response response) async {
          final responseData = response.data;

          // Handle different types of response data
          List<dynamic> coursesData = [];

          if (responseData is List) {
            coursesData = responseData;
          } else if (responseData is Map) {
            // Check if the map contains a list of courses
            if (responseData.containsKey('data') &&
                responseData['data'] is List) {
              coursesData = responseData['data'];
            } else if (responseData.containsKey('courses') &&
                responseData['courses'] is List) {
              coursesData = responseData['courses'];
            } else {
              // Log what we received for debugging
              NyLogger.debug('Featured courses API response: $responseData');
              // Convert to a list if possible
              coursesData = [responseData];
            }
          } else {
            NyLogger.error(
                'Featured courses API returned unexpected type: ${responseData.runtimeType}');

            // Try to handle primitive types
            if (responseData is int ||
                responseData is double ||
                responseData is bool) {
              coursesData = [
                {"value": responseData}
              ];
            } else if (responseData is String) {
              try {
                final parsed = jsonDecode(responseData);
                if (parsed is List) {
                  coursesData = parsed;
                } else {
                  coursesData = [parsed];
                }
              } catch (e) {
                coursesData = [
                  {"text": responseData}
                ];
              }
            } else {
              // Fallback to empty list
              coursesData = [];
            }
          }

          // Cache the processed data
          await storageSave('featured_courses', coursesData);

          // Return the list
          return coursesData;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch featured courses: ${dioError.message}");
        });
  }

  /// Get top courses
  Future<List<dynamic>> getTopCourses({bool refresh = false}) async {
    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead('top_courses');
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/courses/top/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave('top_courses', response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch top courses: ${dioError.message}");
        });
  }

  /// Get all courses with optional filters
  Future<List<dynamic>> getAllCourses({
    int? categoryId,
    String? search,
    String? location,
    bool refresh = false,
  }) async {
    // Create a unique cache key based on filters
    final cacheKey =
        'courses_${categoryId ?? ''}_${search ?? ''}_${location ?? ''}';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    // Build query parameters
    Map<String, dynamic> queryParams = {};
    if (categoryId != null) queryParams['category'] = categoryId.toString();
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (location != null && location.isNotEmpty)
      queryParams['location'] = location;

    return await network(
        request: (request) => request.get(
              "/courses/",
              queryParameters: queryParams,
            ),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch courses: ${dioError.message}");
        });
  }

  /// Get courses by category
  Future<List<dynamic>> getCoursesByCategory(int categoryId,
      {bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'courses_category_$categoryId';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/courses/category/$categoryId/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch courses for category: ${dioError.message}");
        });
  }

  /// Get course details
  Future<dynamic> getCourseDetails(int courseId, {bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'course_details_$courseId';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course details: ${dioError.message}");
        });
  }

  /// Get complete course details (including enrollment info)
  Future<dynamic> getCompleteDetails(int courseId,
      {bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');

    if (authToken == null) {
      // Fallback to regular course details if not authenticated
      return getCourseDetails(courseId, refresh: refresh);
    }

    // Create a cache key
    final cacheKey = 'course_complete_details_$courseId';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) =>
            request.get("/courses/$courseId/complete_details/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          // Fallback to regular course details if API call fails
          return getCourseDetails(courseId, refresh: refresh);
        });
  }

  /// Get user's enrolled courses
  Future<List<dynamic>> getEnrolledCourses({bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Create a cache key
    final cacheKey = 'enrolled_courses';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/enrollments/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch enrolled courses: ${dioError.message}");
        });
  }

  /// Get user's wishlist
  Future<List<dynamic>> getWishlist({bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Create a cache key
    final cacheKey = 'wishlist';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        // Ensure we're returning a List<dynamic>
        if (cached is List) {
          return cached;
        } else if (cached is String) {
          // Try to parse the string as JSON
          try {
            final parsedData = jsonDecode(cached);
            if (parsedData is List) {
              return parsedData;
            }
          } catch (e) {
            // If parsing fails, continue to fetch from network
            NyLogger.error('Error parsing cached wishlist data: $e');
          }
        }
        // If we get here, the cached data is invalid, so we'll fetch fresh data
      }
    }

    return await network(
        request: (request) => request.get("/wishlist/"),
        headers: {
          "Authorization": "Token $authToken",
        },
        handleSuccess: (Response response) async {
          // Cache the data
          // Make sure we're storing the correct data type
          final responseData = response.data;
          print(responseData);
          if (responseData is List) {
            await storageSave(cacheKey, responseData);
          } else {
            NyLogger.error(
                'Wishlist API returned non-list data: $responseData');
          }

          // Return the data as a List
          if (responseData is List) {
            return responseData;
          } else if (responseData is Map) {
            // Some APIs return objects like {"data": []} instead of direct lists
            if (responseData.containsKey('data') &&
                responseData['data'] is List) {
              return responseData['data'];
            }
            // If there's no standard structure, return as a single-item list
            return [responseData];
          } else if (responseData is String) {
            try {
              final parsedData = jsonDecode(responseData);
              if (parsedData is List) {
                return parsedData;
              }
              return [parsedData];
            } catch (e) {
              // If parsing fails, return as a single-item list
              return [responseData];
            }
          }

          // Fallback to empty list
          return [];
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch wishlist: ${dioError.message}");
        });
  }

  /// Add course to wishlist
  Future<dynamic> addToWishlist(int courseId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.post(
              "/wishlist/",
              data: {
                "course": courseId,
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate wishlist cache to force refresh
          await storageDelete('wishlist');

          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to add course to wishlist: ${dioError.message}");
        });
  }

  /// Remove course from wishlist
  Future<bool> removeFromWishlist(int wishlistItemId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/wishlist/$wishlistItemId/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate wishlist cache to force refresh
          await storageDelete('wishlist');

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to remove course from wishlist: ${dioError.message}");
        });
  }

  /// Enroll in a course
  Future<dynamic> enrollInCourse(int courseId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.post(
              "/enrollments/",
              data: {
                "course": courseId,
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate enrolled courses cache to force refresh
          await storageDelete('enrolled_courses');

          // Also invalidate course detail caches for this course
          await storageDelete('course_details_$courseId');
          await storageDelete('course_complete_details_$courseId');

          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to enroll in course: ${dioError.message}");
        });
  }

  /// Get course curriculum
  Future<List<dynamic>> getCourseCurriculum(int courseId,
      {bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'course_curriculum_$courseId';

    // Check cache first if not forcing refresh
    // if (!refresh) {
    //   final cached = await storageRead(cacheKey);
    //   if (cached != null) {
    //     return cached;
    //   }
    // }

    // Get auth token - curriculum might be protected
    final authToken = await backpackRead('auth_token');
    Map<String, String> headers = {};
    if (authToken != null) {
      headers["Authorization"] = "Token ${authToken}";
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/curriculum/"),
        headers: headers,
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course curriculum: ${dioError.message}");
        });
  }

  /// Get course objectives
  Future<List<dynamic>> getCourseObjectives(int courseId,
      {bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'course_objectives_$courseId';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/objectives/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course objectives: ${dioError.message}");
        });
  }

  /// Get course requirements
  Future<List<dynamic>> getCourseRequirements(int courseId,
      {bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'course_requirements_$courseId';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/courses/$courseId/requirements/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch course requirements: ${dioError.message}");
        });
  }

  /// Preload essential data for faster app startup
  Future<void> preloadEssentialData() async {
    try {
      // Get categories, featured courses in parallel
      await Future.wait([
        getFeaturedCourses(),
        getTopCourses(),
        getAllCourses(),
      ]);

      // Check if user is authenticated
      final isAuthenticated = await backpackRead('auth_token') != null;

      // If authenticated, preload user-specific data
      if (isAuthenticated) {
        await Future.wait([
          getEnrolledCourses(),
          getWishlist(),
        ]);
      }
    } catch (e) {
      // Silently handle errors - this is just preloading
      NyLogger.error('Failed to preload some data: ${e.toString()}');
    }
  }
}
