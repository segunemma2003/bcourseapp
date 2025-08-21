import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:nylo_framework/nylo_framework.dart';
import '../networking/payment_link_api_service.dart';

class PlatformPaymentService {
  static final PlatformPaymentService _instance =
      PlatformPaymentService._internal();
  factory PlatformPaymentService() => _instance;
  PlatformPaymentService._internal();

  // Razorpay instance for Android/other platforms
  Razorpay? _razorpay;

  // In-app purchase instance for iOS
  InAppPurchase? _inAppPurchase;

  // Callbacks
  Function(PaymentSuccessResponse)? _onPaymentSuccess;
  Function(PaymentFailureResponse)? _onPaymentError;
  Function(ExternalWalletResponse)? _onExternalWallet;
  Function(PurchaseDetails)? _onInAppPurchaseSuccess;
  Function(String)? _onInAppPurchaseError;
  Function(Map<String, dynamic>)? _onPaymentLinkSuccess;
  Function(String)? _onPaymentLinkError;

  /// Initialize the appropriate payment service based on platform
  Future<void> initialize({
    Function(PaymentSuccessResponse)? onPaymentSuccess,
    Function(PaymentFailureResponse)? onPaymentError,
    Function(ExternalWalletResponse)? onExternalWallet,
    Function(PurchaseDetails)? onInAppPurchaseSuccess,
    Function(String)? onInAppPurchaseError,
    Function(Map<String, dynamic>)? onPaymentLinkSuccess,
    Function(String)? onPaymentLinkError,
  }) async {
    _onPaymentSuccess = onPaymentSuccess;
    _onPaymentError = onPaymentError;
    _onExternalWallet = onExternalWallet;
    _onInAppPurchaseSuccess = onInAppPurchaseSuccess;
    _onInAppPurchaseError = onInAppPurchaseError;
    _onPaymentLinkSuccess = onPaymentLinkSuccess;
    _onPaymentLinkError = onPaymentLinkError;

    if (Platform.isIOS) {
      // For iOS, we'll use payment link API instead of in-app purchase
      NyLogger.info('✅ iOS platform detected - using Payment Link API');
    } else {
      await _initializeRazorpay();
    }
  }

  /// Initialize Razorpay for Android/other platforms
  Future<void> _initializeRazorpay() async {
    try {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
      _razorpay!
          .on(Razorpay.EVENT_EXTERNAL_WALLET, _handleRazorpayExternalWallet);
      NyLogger.info('✅ Razorpay initialized successfully');
    } catch (e) {
      NyLogger.error('❌ Error initializing Razorpay: $e');
      rethrow;
    }
  }

  /// Initialize in-app purchase for iOS
  Future<void> _initializeInAppPurchase() async {
    try {
      _inAppPurchase = InAppPurchase.instance;

      // Check if in-app purchases are available
      final bool available = await _inAppPurchase!.isAvailable();
      if (!available) {
        throw Exception('In-app purchases are not available on this device');
      }

      NyLogger.info('✅ In-app purchase initialized successfully');
    } catch (e) {
      NyLogger.error('❌ Error initializing in-app purchase: $e');
      rethrow;
    }
  }

  /// Start payment process with platform-specific implementation
  Future<void> startPayment({
    required String courseId,
    required String planType,
    required String amount,
    required String courseTitle,
    required Map<String, dynamic> userInfo,
    Map<String, dynamic>? orderDetails,
  }) async {
    if (Platform.isIOS) {
      await _startPaymentLinkRequest(
        courseId: courseId,
        planType: planType,
        amount: amount,
        courseTitle: courseTitle,
        userInfo: userInfo,
      );
    } else {
      await _startRazorpayPayment(
        courseId: courseId,
        planType: planType,
        amount: amount,
        courseTitle: courseTitle,
        userInfo: userInfo,
        orderDetails: orderDetails,
      );
    }
  }

  /// Start Razorpay payment
  Future<void> _startRazorpayPayment({
    required String courseId,
    required String planType,
    required String amount,
    required String courseTitle,
    required Map<String, dynamic> userInfo,
    Map<String, dynamic>? orderDetails,
  }) async {
    if (_razorpay == null) {
      throw Exception('Razorpay not initialized');
    }

    try {
      var options = {
        'key': orderDetails?['key_id'] ?? getEnv('RAZORPAY_KEY_ID'),
        'order_id': orderDetails?['order_id'] ?? '',
        'amount': orderDetails?['amount'] != null
            ? (orderDetails!['amount'] * 100).toInt()
            : (double.parse(amount) * 100).toInt(),
        'currency': orderDetails?['currency'] ?? 'INR',
        'name': 'Course Enrollment',
        'description': 'Enrollment for $courseTitle',
        'prefill': {
          'email': userInfo['email'] ?? '',
          'name': userInfo['name'] ?? '',
          'contact': userInfo['phone'] ?? '',
        },
        'notes': {
          'course_id': courseId,
          'plan_type': planType,
        },
        'theme': {
          'color': '#EFE458',
        }
      };

      NyLogger.info('🚀 Opening Razorpay payment interface...');
      _razorpay!.open(options);
    } catch (e) {
      NyLogger.error('❌ Razorpay payment error: $e');
      rethrow;
    }
  }

  /// Start payment link request for iOS
  Future<void> _startPaymentLinkRequest({
    required String courseId,
    required String planType,
    required String amount,
    required String courseTitle,
    required Map<String, dynamic> userInfo,
  }) async {
    try {
      final paymentLinkService = PaymentLinkApiService();

      NyLogger.info('🚀 Creating payment link request for iOS...');

      // Create payment link request
      final result = await paymentLinkService.createPaymentLink(
        courseId: int.parse(courseId),
        planType: planType,
        amount: double.tryParse(amount),
      );

      if (result['success'] == true) {
        NyLogger.info('✅ Payment link created successfully');
        _onPaymentLinkSuccess?.call(result);
      } else {
        throw Exception('Failed to create payment link');
      }
    } catch (e) {
      NyLogger.error('❌ Payment link request error: $e');
      _onPaymentLinkError?.call(e.toString());
      rethrow;
    }
  }

  /// Generate product ID for in-app purchase
  String _getProductId(String planType, String courseId) {
    // Format: course_{courseId}_{planType}
    // Example: course_123_lifetime, course_123_monthly
    return 'course_${courseId}_${planType.toLowerCase()}';
  }

  /// Handle Razorpay payment success
  void _handleRazorpaySuccess(PaymentSuccessResponse response) {
    NyLogger.info('✅ Razorpay payment successful: ${response.paymentId}');
    _onPaymentSuccess?.call(response);
  }

  /// Handle Razorpay payment error
  void _handleRazorpayError(PaymentFailureResponse response) {
    NyLogger.error('❌ Razorpay payment failed: ${response.message}');
    _onPaymentError?.call(response);
  }

  /// Handle Razorpay external wallet
  void _handleRazorpayExternalWallet(ExternalWalletResponse response) {
    NyLogger.info('📱 Razorpay external wallet: ${response.walletName}');
    _onExternalWallet?.call(response);
  }

  /// Handle in-app purchase success
  void _handleInAppPurchaseSuccess(PurchaseDetails purchaseDetails) {
    NyLogger.info('✅ In-app purchase successful: ${purchaseDetails.productID}');
    _onInAppPurchaseSuccess?.call(purchaseDetails);
  }

  /// Handle in-app purchase error
  void _handleInAppPurchaseError(String error) {
    NyLogger.error('❌ In-app purchase failed: $error');
    _onInAppPurchaseError?.call(error);
  }

  /// Listen to in-app purchase updates
  void listenToInAppPurchaseUpdates() {
    if (Platform.isIOS && _inAppPurchase != null) {
      _inAppPurchase!.purchaseStream
          .listen((List<PurchaseDetails> purchaseDetailsList) {
        for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
          if (purchaseDetails.status == PurchaseStatus.pending) {
            NyLogger.info(
                '⏳ In-app purchase pending: ${purchaseDetails.productID}');
          } else if (purchaseDetails.status == PurchaseStatus.purchased) {
            _handleInAppPurchaseSuccess(purchaseDetails);
          } else if (purchaseDetails.status == PurchaseStatus.error) {
            _handleInAppPurchaseError(
                purchaseDetails.error?.message ?? 'Unknown error');
          } else if (purchaseDetails.status == PurchaseStatus.canceled) {
            NyLogger.info(
                '❌ In-app purchase canceled: ${purchaseDetails.productID}');
          }
        }
      });
    }
  }

  /// Complete in-app purchase
  Future<void> completeInAppPurchase(PurchaseDetails purchaseDetails) async {
    if (Platform.isIOS && _inAppPurchase != null) {
      await _inAppPurchase!.completePurchase(purchaseDetails);
    }
  }

  /// Dispose resources
  void dispose() {
    if (Platform.isIOS) {
      // In-app purchase doesn't need explicit disposal
    } else {
      _razorpay?.clear();
      _razorpay = null;
    }
  }

  /// Check if current platform supports the payment method
  bool get isPaymentSupported {
    if (Platform.isIOS) {
      return _inAppPurchase != null;
    } else {
      return _razorpay != null;
    }
  }

  /// Get platform name for logging
  String get platformName {
    if (Platform.isIOS) {
      return 'iOS Payment Link API';
    } else {
      return 'Android Razorpay';
    }
  }
}
