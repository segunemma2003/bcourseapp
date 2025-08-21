import 'package:nylo_framework/nylo_framework.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class PaymentLinkApiService extends NyApiService {
  PaymentLinkApiService({BuildContext? buildContext})
      : super(buildContext, decoders: {});

  @override
  String get baseUrl => getEnv('API_BASE_URL') + "/api";

  /// Create payment link request for iOS
  Future<Map<String, dynamic>> createPaymentLink({
    required int courseId,
    required String planType,
    double? amount,
  }) async {
    final authToken = await backpackRead('auth_token');
    if (authToken == null) {
      throw Exception("Not logged in");
    }

    Map<String, dynamic> data = {
      "course_id": courseId,
      "plan_type": planType,
    };

    if (amount != null) {
      data["amount"] = amount;
    }

    try {
      return await network(
        request: (request) =>
            request.post("/payment-links/create/", data: data),
        headers: {
          "Authorization": "Token $authToken",
          "Content-Type": "application/json",
        },
        handleSuccess: (Response response) {
          NyLogger.info('✅ Payment link created successfully');
          NyLogger.debug('Payment link response: ${response.data}');
          return response.data;
        },
        handleFailure: (DioException dioError) {
          String errorMessage = "Failed to create payment link";

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
              NyLogger.error('Error parsing payment link error response: $e');
            }
          }

          NyLogger.error('❌ Create payment link failed: $errorMessage');
          throw Exception("$errorMessage: ${dioError.message}");
        },
      );
    } catch (e) {
      NyLogger.error('❌ Create payment link error: $e');
      rethrow;
    }
  }
}
