import 'dart:convert';

import 'package:flutter/material.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CategoryApiService extends NyApiService {
  CategoryApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  /// Get all categories
  Future<List<dynamic>> getCategories({bool refresh = false}) async {
    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead('categories');
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/categories/"),
        handleSuccess: (Response response) async {
          // Cache the data

          await storageSave('categories', response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch categories: ${dioError.message}");
        });
  }

  Future<void> preloadEssentialData() async {
    try {
      // Get categories, featured courses in parallel
      await Future.wait([
        getCategories(),
      ]);
    } catch (e) {
      // Silently handle errors - this is just preloading
      NyLogger.error('Failed to preload some data: ${e.toString()}');
    }
  }
}
