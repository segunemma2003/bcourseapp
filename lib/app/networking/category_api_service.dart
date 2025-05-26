import 'package:flutter/material.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CategoryApiService extends NyApiService {
  CategoryApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  // Cache duration constants
  static const Duration CACHE_CATEGORIES = Duration(hours: 24);
  static const Duration CACHE_CATEGORY_DETAILS = Duration(hours: 12);
  static const Duration CACHE_CATEGORIES_WITH_COUNT = Duration(hours: 12);

  /// Get all categories with intelligent caching
  Future<List<dynamic>> getCategories({bool refresh = false}) async {
    if (refresh) {
      // Force refresh by clearing cache first
      await cache().clear('categories');
    }

    return await network(
        request: (request) => request.get("/categories/"),
        cacheKey: "categories",
        cacheDuration: CACHE_CATEGORIES,
        handleSuccess: (Response response) async {
          // Handle different response structures
          final responseData = response.data;

          if (responseData is List) {
            return responseData;
          } else if (responseData is Map) {
            // Check common keys for list data
            if (responseData.containsKey('data') &&
                responseData['data'] is List) {
              return responseData['data'];
            } else if (responseData.containsKey('categories') &&
                responseData['categories'] is List) {
              return responseData['categories'];
            } else {
              return [responseData];
            }
          } else {
            // Handle edge cases
            return responseData != null ? [responseData] : [];
          }
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch categories: ${dioError.message}");
        });
  }

  /// Get category details with caching
  Future<dynamic> getCategoryDetails(int categoryId,
      {bool refresh = false}) async {
    final cacheKey = 'category_details_$categoryId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/categories/$categoryId/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_CATEGORY_DETAILS,
        handleSuccess: (Response response) => response.data,
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch category details: ${dioError.message}");
        });
  }

  /// Get categories with course count
  Future<List<dynamic>> getCategoriesWithCourseCount(
      {bool refresh = false}) async {
    const cacheKey = 'categories_with_count';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/categories/with-course-count/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_CATEGORIES_WITH_COUNT,
        handleSuccess: (Response response) {
          final responseData = response.data;
          return responseData is List
              ? responseData
              : responseData is Map && responseData.containsKey('data')
                  ? responseData['data']
                  : [];
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch categories with course count: ${dioError.message}");
        });
  }

  /// Invalidate category caches (call after updates)
  Future<void> invalidateCaches({int? categoryId}) async {
    if (categoryId != null) {
      // Invalidate specific category
      await cache().clear('category_details_$categoryId');
    } else {
      // Invalidate all category caches
      await Future.wait([
        cache().clear('categories'),
        cache().clear('categories_with_count'),
      ]);
    }
  }

  /// Get cached categories without network call (returns null if not cached)
  Future<List<dynamic>?> getCachedCategories() async {
    return await cache().get('categories');
  }

  /// Check if categories are cached
  Future<bool> areCategoriesCached() async {
    return await cache().has('categories');
  }

  /// Preload essential data with parallel loading
  Future<void> preloadEssentialData() async {
    try {
      // Load categories in parallel with individual error handling
      await Future.wait([
        getCategories().catchError((e) {
          NyLogger.error('Failed to preload categories: $e');
          return <dynamic>[];
        }),
        getCategoriesWithCourseCount().catchError((e) {
          NyLogger.error('Failed to preload categories with count: $e');
          return <dynamic>[];
        }),
      ]);

      NyLogger.info('Category data preloading completed');
    } catch (e) {
      NyLogger.error('Failed to preload category data: ${e.toString()}');
    }
  }

  /// Warm up cache by forcing fresh data load
  Future<void> warmUpCache() async {
    try {
      await Future.wait([
        getCategories(refresh: true),
        getCategoriesWithCourseCount(refresh: true),
      ]);
      NyLogger.info('Category cache warmed up successfully');
    } catch (e) {
      NyLogger.error('Failed to warm up category cache: $e');
    }
  }
}
