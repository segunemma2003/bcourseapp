import 'package:flutter/material.dart';
import '/config/decoders.dart';
import 'package:nylo_framework/nylo_framework.dart';

class PurchaseApiService extends NyApiService {
  PurchaseApiService({BuildContext? buildContext})
      : super(buildContext, decoders: modelDecoders);

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  // Cache duration constants
  static const Duration CACHE_SUBSCRIPTION_PLANS = Duration(hours: 24);
  static const Duration CACHE_SUBSCRIPTION_PLAN_DETAILS = Duration(hours: 24);
  static const Duration CACHE_USER_SUBSCRIPTIONS = Duration(hours: 2);
  static const Duration CACHE_PAYMENT_CARDS = Duration(hours: 2);
  static const Duration CACHE_PURCHASE_HISTORY = Duration(hours: 4);
  static const Duration CACHE_APP_SETTINGS = Duration(days: 1);
  static const Duration CACHE_CONTENT_PAGES = Duration(days: 2);

  /// Get all subscription plans with long-term caching
  Future<List<dynamic>> getSubscriptionPlans({bool refresh = false}) async {
    const cacheKey = 'subscription_plans';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/subscription-plans/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_SUBSCRIPTION_PLANS,
        handleSuccess: (Response response) {
          return _parseListResponse(response.data, 'subscription plans');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch subscription plans: ${dioError.message}");
        });
  }

  /// Get subscription plan details with caching
  Future<dynamic> getSubscriptionPlanDetails(int planId,
      {bool refresh = false}) async {
    final cacheKey = 'subscription_plan_$planId';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/subscription-plans/$planId/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_SUBSCRIPTION_PLAN_DETAILS,
        handleSuccess: (Response response) => response.data,
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch subscription plan details: ${dioError.message}");
        });
  }

  /// Get user's active subscriptions with moderate caching
  Future<List<dynamic>> getUserSubscriptions({bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    const cacheKey = 'user_subscriptions';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/my-subscriptions/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_USER_SUBSCRIPTIONS,
        handleSuccess: (Response response) {
          return _parseListResponse(response.data, 'user subscriptions');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch user subscriptions: ${dioError.message}");
        });
  }

  /// Check if user has active subscription (uses cached data)
  Future<bool> hasActiveSubscription({bool refresh = false}) async {
    try {
      final subscriptions = await getUserSubscriptions(refresh: refresh);
      return subscriptions
          .any((sub) => sub['is_active'] == true && sub['is_expired'] == false);
    } catch (e) {
      return false;
    }
  }

  /// Subscribe to a plan (invalidates subscription caches)
  Future<dynamic> subscribeToPlan(int planId, {DateTime? endDate}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    final subscriptionEndDate =
        endDate ?? DateTime.now().add(Duration(days: 365));

    return await network(
        request: (request) => request.post("/my-subscriptions/", data: {
              "plan": planId,
              "end_date": subscriptionEndDate.toIso8601String(),
            }),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate subscription-related caches
          await _invalidateSubscriptionCaches();
          return response.data;
        },
        handleFailure: (DioException dioError) {
          String errorMessage = "Failed to subscribe to plan";

          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors is Map) {
              final errorKeys = errors.keys;
              if (errorKeys.isNotEmpty) {
                final firstKey = errorKeys.first;
                final errorList = errors[firstKey];
                if (errorList is List && errorList.isNotEmpty) {
                  errorMessage = errorList.first.toString();
                }
              }
            }
          }

          throw Exception("$errorMessage: ${dioError.message}");
        });
  }

  /// Cancel subscription (invalidates subscription caches)
  Future<bool> cancelSubscription(int subscriptionId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) =>
            request.delete("/my-subscriptions/$subscriptionId/"),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate subscription caches
          await _invalidateSubscriptionCaches();
          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to cancel subscription: ${dioError.message}");
        });
  }

  /// Get user's payment cards with caching
  Future<List<dynamic>> getPaymentCards({bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    const cacheKey = 'payment_cards';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/payment-cards/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_PAYMENT_CARDS,
        handleSuccess: (Response response) {
          return _parseListResponse(response.data, 'payment cards');
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch payment cards: ${dioError.message}");
        });
  }

  /// Add a payment card (invalidates payment cards cache)
  Future<dynamic> addPaymentCard({
    required String cardType,
    required String lastFour,
    required String cardHolderName,
    required String expiryMonth,
    required String expiryYear,
    bool isDefault = false,
  }) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.post("/payment-cards/", data: {
              "card_type": cardType,
              "last_four": lastFour,
              "card_holder_name": cardHolderName,
              "expiry_month": expiryMonth,
              "expiry_year": expiryYear,
              "is_default": isDefault,
            }),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate payment cards cache
          await cache().clear('payment_cards');
          return response.data;
        },
        handleFailure: (DioException dioError) {
          String errorMessage = "Failed to add payment card";

          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors is Map) {
              final errorKeys = errors.keys;
              if (errorKeys.isNotEmpty) {
                final firstKey = errorKeys.first;
                final errorList = errors[firstKey];
                if (errorList is List && errorList.isNotEmpty) {
                  errorMessage = errorList.first.toString();
                }
              }
            }
          }

          throw Exception(errorMessage);
        });
  }

  /// Update a payment card (invalidates payment cards cache)
  Future<dynamic> updatePaymentCard({
    required int cardId,
    required String cardType,
    required String lastFour,
    required String cardHolderName,
    required String expiryMonth,
    required String expiryYear,
    bool isDefault = false,
  }) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.put("/payment-cards/$cardId/", data: {
              "card_type": cardType,
              "last_four": lastFour,
              "card_holder_name": cardHolderName,
              "expiry_month": expiryMonth,
              "expiry_year": expiryYear,
              "is_default": isDefault,
            }),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate payment cards cache
          await cache().clear('payment_cards');
          return response.data;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to update payment card: ${dioError.message}");
        });
  }

  /// Delete a payment card (invalidates payment cards cache)
  Future<bool> deletePaymentCard(int cardId) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    return await network(
        request: (request) => request.delete("/payment-cards/$cardId/"),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate payment cards cache
          await cache().clear('payment_cards');
          return true;
        },
        handleFailure: (DioException dioError) {
          throw Exception("Failed to delete payment card: ${dioError.message}");
        });
  }

  /// Get purchase history with caching
  Future<List<dynamic>> getPurchaseHistory({bool refresh = false}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    const cacheKey = 'purchase_history';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/purchase-history/"),
        headers: {"Authorization": "Token $authToken"},
        cacheKey: cacheKey,
        cacheDuration: CACHE_PURCHASE_HISTORY,
        handleSuccess: (Response response) {
          return _parseListResponse(response.data, 'purchase history');
        },
        handleFailure: (DioException dioError) {
          throw Exception(
              "Failed to fetch purchase history: ${dioError.message}");
        });
  }

  /// Purchase a course (invalidates relevant caches)
  Future<dynamic> purchaseCourse(int courseId, {int? paymentCardId}) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    Map<String, dynamic> data = {
      "course": courseId,
      "amount": "0.00",
      "transaction_id": "manual-${DateTime.now().millisecondsSinceEpoch}",
    };

    if (paymentCardId != null) {
      data["payment_card"] = paymentCardId;
    }

    return await network(
        request: (request) => request.post("/purchase-history/", data: data),
        headers: {"Authorization": "Token $authToken"},
        handleSuccess: (Response response) async {
          // Invalidate purchase and enrollment related caches
          await _invalidatePostPurchaseCaches();
          return response.data;
        },
        handleFailure: (DioException dioError) {
          String errorMessage = "Failed to purchase course";

          if (dioError.response?.data != null) {
            final errors = dioError.response!.data;
            if (errors is Map) {
              final errorKeys = errors.keys;
              if (errorKeys.isNotEmpty) {
                final firstKey = errorKeys.first;
                final errorList = errors[firstKey];
                if (errorList is List && errorList.isNotEmpty) {
                  errorMessage = errorList.first.toString();
                }
              }
            }
          }

          throw Exception(errorMessage);
        });
  }

  /// Get app settings with long-term caching
  Future<dynamic> getAppSettings({bool refresh = false}) async {
    const cacheKey = 'app_settings';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/settings/"),
        cacheKey: cacheKey,
        cacheDuration: CACHE_APP_SETTINGS,
        handleSuccess: (Response response) => response.data,
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch app settings: ${dioError.message}");
        });
  }

  /// Get content pages with very long-term caching
  Future<dynamic> getContentPage(String pageType,
      {bool refresh = false}) async {
    final cacheKey = 'content_page_${pageType.toLowerCase()}';

    if (refresh) {
      await cache().clear(cacheKey);
    }

    return await network(
        request: (request) => request.get("/content/", queryParameters: {
              "page_type": pageType,
            }),
        cacheKey: cacheKey,
        cacheDuration: CACHE_CONTENT_PAGES,
        handleSuccess: (Response response) => response.data,
        handleFailure: (DioException dioError) {
          throw Exception("Failed to fetch content page: ${dioError.message}");
        });
  }

  /// Get cached subscription plans (fast access)
  Future<List<dynamic>?> getCachedSubscriptionPlans() async {
    return await cache().get('subscription_plans');
  }

  /// Get cached user subscriptions (fast access)
  Future<List<dynamic>?> getCachedUserSubscriptions() async {
    return await cache().get('user_subscriptions');
  }

  /// Get cached payment cards (fast access)
  Future<List<dynamic>?> getCachedPaymentCards() async {
    return await cache().get('payment_cards');
  }

  /// Check cache status for debugging
  Future<Map<String, bool>> getCacheStatus() async {
    return {
      'subscription_plans': await cache().has('subscription_plans'),
      'user_subscriptions': await cache().has('user_subscriptions'),
      'payment_cards': await cache().has('payment_cards'),
      'purchase_history': await cache().has('purchase_history'),
      'app_settings': await cache().has('app_settings'),
    };
  }

  /// Preload subscription data with parallel loading
  Future<void> preloadSubscriptionData() async {
    try {
      // Load subscription plans (public data)
      await getSubscriptionPlans().catchError((e) {
        NyLogger.error('Failed to preload subscription plans: $e');
        return <dynamic>[];
      });

      // Check if user is authenticated
      final isAuthenticated = await backpackRead('auth_token') != null;

      if (isAuthenticated) {
        // Load user-specific data in parallel
        await Future.wait([
          getUserSubscriptions().catchError((e) {
            NyLogger.error('Failed to preload user subscriptions: $e');
            return <dynamic>[];
          }),
          getPaymentCards().catchError((e) {
            NyLogger.error('Failed to preload payment cards: $e');
            return <dynamic>[];
          }),
          getPurchaseHistory().catchError((e) {
            NyLogger.error('Failed to preload purchase history: $e');
            return <dynamic>[];
          }),
        ]);
      }

      // Load content pages and app settings in parallel
      await Future.wait([
        getContentPage("PRIVACY").catchError((e) {
          NyLogger.error('Failed to preload privacy policy: $e');
          return {};
        }),
        getContentPage("TERMS").catchError((e) {
          NyLogger.error('Failed to preload terms: $e');
          return {};
        }),
        getAppSettings().catchError((e) {
          NyLogger.error('Failed to preload app settings: $e');
          return {};
        }),
      ]);

      NyLogger.info('Subscription data preloading completed');
    } catch (e) {
      NyLogger.error('Failed to preload subscription data: ${e.toString()}');
    }
  }

  /// Force refresh all purchase-related data
  Future<void> refreshAllPurchaseData() async {
    try {
      final isAuthenticated = await backpackRead('auth_token') != null;

      if (isAuthenticated) {
        await Future.wait([
          getUserSubscriptions(refresh: true),
          getPaymentCards(refresh: true),
          getPurchaseHistory(refresh: true),
        ]);
        NyLogger.info('All purchase data refreshed');
      }
    } catch (e) {
      NyLogger.error('Failed to refresh purchase data: $e');
    }
  }

  // Helper methods

  /// Parse list responses consistently
  List<dynamic> _parseListResponse(dynamic responseData, String context) {
    try {
      if (responseData is List) {
        return responseData;
      } else if (responseData is Map) {
        // Check common keys for list data
        final possibleKeys = [
          'data',
          'results',
          'items',
          context.toLowerCase().replaceAll(' ', '_')
        ];

        for (final key in possibleKeys) {
          if (responseData.containsKey(key) && responseData[key] is List) {
            return responseData[key];
          }
        }

        return [responseData];
      }

      return responseData != null ? [responseData] : [];
    } catch (e) {
      NyLogger.error('Error parsing $context response: $e');
      return [];
    }
  }

  /// Invalidate subscription-related caches
  Future<void> _invalidateSubscriptionCaches() async {
    await Future.wait([
      cache().clear('user_subscriptions'),
      cache().clear('purchase_history'),
    ]);
  }

  /// Invalidate caches after purchase
  Future<void> _invalidatePostPurchaseCaches() async {
    await Future.wait([
      cache().clear('purchase_history'),
      cache().clear('enrolled_courses'), // This might be in CourseApiService
    ]);
  }
}
