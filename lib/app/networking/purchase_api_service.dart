import 'dart:convert';

import 'package:flutter/material.dart';

import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class PurchaseApiService extends NyApiService {
  PurchaseApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  /// Get all subscription plans
  Future<List<dynamic>> getSubscriptionPlans({bool refresh = false}) async {
    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead('subscription_plans');
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/subscription-plans/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave('subscription_plans', response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch subscription plans: ${dioError.message}");
        });
  }

  /// Get subscription plan details
  Future<dynamic> getSubscriptionPlanDetails(int planId,
      {bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'subscription_plan_$planId';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/subscription-plans/$planId/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch subscription plan details: ${dioError.message}");
        });
  }

  /// Get user's active subscriptions
  Future<List<dynamic>> getUserSubscriptions({bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Create a cache key
    final cacheKey = 'user_subscriptions';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/my-subscriptions/"),
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
              "Failed to fetch user subscriptions: ${dioError.message}");
        });
  }

  /// Check if user has active subscription
  Future<bool> hasActiveSubscription() async {
    try {
      final subscriptions = await getUserSubscriptions();
      return subscriptions
          .any((sub) => sub['is_active'] == true && sub['is_expired'] == false);
    } catch (e) {
      return false;
    }
  }

  /// Subscribe to a plan
  Future<dynamic> subscribeToPlan(int planId, {DateTime? endDate}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Default to 1 year subscription if no end date provided
    final subscriptionEndDate =
        endDate ?? DateTime.now().add(Duration(days: 365));

    return await network(
        request: (request) => request.post(
              "/my-subscriptions/",
              data: {
                "plan": planId,
                "end_date": subscriptionEndDate.toIso8601String(),
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate subscriptions cache
          await storageDelete('user_subscriptions');

          return response.data;
        },
        handleFailure: (DioException dioError) {
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors is Map) {
              final errorKeys = errors.keys;
              if (errorKeys.isNotEmpty) {
                final firstKey = errorKeys.first;
                final errorList = errors[firstKey];
                if (errorList is List && errorList.isNotEmpty) {
                  throw Exception(errorList.first.toString());
                }
              }
            }
          }
          throw Exception("Failed to subscribe to plan: ${dioError.message}");
        });
  }

  /// Cancel subscription
  Future<bool> cancelSubscription(int subscriptionId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) =>
            request.delete("/my-subscriptions/$subscriptionId/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate subscriptions cache
          await storageDelete('user_subscriptions');

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to cancel subscription: ${dioError.message}");
        });
  }

  /// Get user's payment cards
  Future<List<dynamic>> getPaymentCards({bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Create a cache key
    final cacheKey = 'payment_cards';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/payment-cards/"),
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
          throw Exception("Failed to fetch payment cards: ${dioError.message}");
        });
  }

  /// Add a payment card
  Future<dynamic> addPaymentCard({
    required String cardType,
    required String lastFour,
    required String cardHolderName,
    required String expiryMonth,
    required String expiryYear,
    bool isDefault = false,
  }) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.post(
              "/payment-cards/",
              data: {
                "card_type": cardType,
                "last_four": lastFour,
                "card_holder_name": cardHolderName,
                "expiry_month": expiryMonth,
                "expiry_year": expiryYear,
                "is_default": isDefault,
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate payment cards cache
          await storageDelete('payment_cards');

          return response.data;
        },
        handleFailure: (DioException dioError) {
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors is Map) {
              final errorKeys = errors.keys;
              if (errorKeys.isNotEmpty) {
                final firstKey = errorKeys.first;
                final errorList = errors[firstKey];
                if (errorList is List && errorList.isNotEmpty) {
                  throw Exception(errorList.first.toString());
                }
              }
            }
          }
          throw Exception("Failed to add payment card: ${dioError.message}");
        });
  }

  /// Update a payment card
  Future<dynamic> updatePaymentCard({
    required int cardId,
    required String cardType,
    required String lastFour,
    required String cardHolderName,
    required String expiryMonth,
    required String expiryYear,
    bool isDefault = false,
  }) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.put(
              "/payment-cards/$cardId/",
              data: {
                "card_type": cardType,
                "last_four": lastFour,
                "card_holder_name": cardHolderName,
                "expiry_month": expiryMonth,
                "expiry_year": expiryYear,
                "is_default": isDefault,
              },
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate payment cards cache
          await storageDelete('payment_cards');

          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to update payment card: ${dioError.message}");
        });
  }

  /// Delete a payment card
  Future<bool> deletePaymentCard(int cardId) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/payment-cards/$cardId/"),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate payment cards cache
          await storageDelete('payment_cards');

          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to delete payment card: ${dioError.message}");
        });
  }

  /// Get purchase history
  Future<List<dynamic>> getPurchaseHistory({bool refresh = false}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Create a cache key
    final cacheKey = 'purchase_history';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/purchase-history/"),
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
              "Failed to fetch purchase history: ${dioError.message}");
        });
  }

  /// Purchase a course
  Future<dynamic> purchaseCourse(int courseId, {int? paymentCardId}) async {
    // Get auth token
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    // Prepare request data
    Map<String, dynamic> data = {
      "course": courseId,
      "amount":
          "0.00", // This would typically come from the course price or be calculated server-side
      "transaction_id":
          "manual-${DateTime.now().millisecondsSinceEpoch}", // In a real implementation, this would come from a payment gateway
    };

    // Add payment card if provided
    if (paymentCardId != null) {
      data["payment_card"] = paymentCardId;
    }

    return await network(
        request: (request) => request.post(
              "/purchase-history/",
              data: data,
            ),
        headers: {
          "Authorization": "Token ${authToken}",
        },
        handleSuccess: (Response response) async {
          // Invalidate purchase history and enrollments caches
          await storageDelete('purchase_history');
          await storageDelete('enrolled_courses');

          return response.data;
        },
        handleFailure: (DioException dioError) {
          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors is Map) {
              final errorKeys = errors.keys;
              if (errorKeys.isNotEmpty) {
                final firstKey = errorKeys.first;
                final errorList = errors[firstKey];
                if (errorList is List && errorList.isNotEmpty) {
                  throw Exception(errorList.first.toString());
                }
              }
            }
          }
          throw Exception("Failed to purchase course: ${dioError.message}");
        });
  }

  /// Get app settings
  Future<dynamic> getAppSettings({bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'app_settings';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get("/settings/"),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch app settings: ${dioError.message}");
        });
  }

  /// Get content pages (privacy policy, terms)
  Future<dynamic> getContentPage(String pageType,
      {bool refresh = false}) async {
    // Create a cache key
    final cacheKey = 'content_page_${pageType.toLowerCase()}';

    // Check cache first if not forcing refresh
    if (!refresh) {
      final cached = await storageRead(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    return await network(
        request: (request) => request.get(
              "/content/",
              queryParameters: {
                "page_type": pageType,
              },
            ),
        handleSuccess: (Response response) async {
          // Cache the data
          await storageSave(cacheKey, response.data);

          // Return the data
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch content page: ${dioError.message}");
        });
  }

  /// Preload subscription data
  Future<void> preloadSubscriptionData() async {
    try {
      // Get subscription plans
      await getSubscriptionPlans();

      // Check if user is authenticated
      final isAuthenticated = await backpackRead('auth_token') != null;

      // If authenticated, preload user-specific subscription data
      if (isAuthenticated) {
        await Future.wait([
          getUserSubscriptions(),
          getPaymentCards(),
          getPurchaseHistory(),
        ]);
      }

      // Get content pages
      await Future.wait([
        getContentPage("PRIVACY"),
        getContentPage("TERMS"),
      ]);

      // Get app settings
      await getAppSettings();
    } catch (e) {
      // Silently handle errors - this is just preloading
      NyLogger.error('Failed to preload subscription data: ${e.toString()}');
    }
  }
}
