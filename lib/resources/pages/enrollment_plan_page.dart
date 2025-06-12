import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/app/services/video_service.dart';
import 'package:flutter_app/resources/pages/base_navigation_hub.dart';
import 'package:flutter_app/resources/pages/course_curriculum_page.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../app/models/course.dart';
import '../../app/models/enrollment.dart';
import '../../app/networking/course_api_service.dart';
import 'package:uuid/uuid.dart';

class EnrollmentPlanPage extends NyStatefulWidget {
  static RouteView path = ("/enrollment-plan", (_) => EnrollmentPlanPage());

  EnrollmentPlanPage({super.key})
      : super(child: () => _EnrollmentPlanPageState());
}

class _EnrollmentPlanPageState extends NyPage<EnrollmentPlanPage> {
  Course? course;
  int selectedPlanIndex = 0;
  List<SubscriptionPlan> subscriptionPlans = [];
  bool _isProcessingPayment = false;
  VideoService _videoService = VideoService();
  bool isRenewal = false;

  late Razorpay _razorpay;
  List<dynamic> curriculumItems = [];
  String? username;
  String? email;
  Course? _previousCourse;
  String? _previousSubscriptionStatus;
  DateTime? _previousExpiryDate;
  DateTime? _paymentStartTime;
  Timer? _paymentTimeoutTimer;

  bool _isCreatingOrder = false;
  bool _isVerifyingPayment = false;
  bool _isCompletingEnrollment = false;
  String _currentLoadingMessage = "";

  // ✅ NEW: Store order details
  Map<String, dynamic>? _currentOrderDetails;
  String? _currentOrderId;

  bool get _isAnyProcessActive =>
      _isCreatingOrder ||
      _isProcessingPayment ||
      _isVerifyingPayment ||
      _isCompletingEnrollment;
  @override
  void initState() {
    super.initState();

    try {
      _razorpay = Razorpay();
      _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    } catch (e) {
      NyLogger.error('Error initializing Razorpay: $e');
    }
  }

  @override
  void dispose() {
    try {
      _paymentTimeoutTimer?.cancel();
      _razorpay.clear();
    } catch (e) {
      NyLogger.error('Error disposing Razorpay: $e');
    }
    super.dispose();
  }

  @override
  get init => () async {
        setLoading(true, name: 'fetch_plans');

        Map<String, dynamic> data = widget.data();
        if (data.containsKey('course') && data['course'] != null) {
          course = data['course'];
          _previousCourse = course;
          _previousSubscriptionStatus = course!.subscriptionStatus;
          _previousExpiryDate = course!.subscriptionExpiryDate;
        } else {
          showToastWarning(description: trans("Course information is missing"));
          pop();
          return;
        }

        if (data.containsKey('isRenewal') && data['isRenewal'] == true) {
          isRenewal = true;
        }

        if (isRenewal) {
          await _validateCurrentSubscriptionStatus();
        }
        // Get curriculum from data if available, otherwise fetch it
        if (data.containsKey('curriculum') && data['curriculum'] != null) {
          curriculumItems = data['curriculum'];
        } else {
          // Only fetch if not provided
          await _fetchCurriculum();
        }

        try {
          var user = await Auth.data();
          if (user != null) {
            username = user['full_name'] ?? "User";
            email = user['email'] ?? "";
          }
        } catch (e) {
          NyLogger.error('Error getting username: $e');
        }

        try {
          subscriptionPlans = [
            SubscriptionPlan(
              id: 2,
              name: "Quarterly Access",
              amount: course!.priceThreeMonths,
              planType: "THREE_MONTHS",
              isPro: false,
              features: [
                PlanFeature(
                    id: 5, description: "Full course access for 3 months"),
                PlanFeature(id: 7, description: "Priority support"),
              ],
            ),
            SubscriptionPlan(
              id: 3,
              name: "Lifetime Access",
              amount: course!.priceLifetime,
              planType: "LIFETIME",
              isPro: true,
              features: [
                PlanFeature(
                    id: 10,
                    description: "Unlimited lifetime access to the course"),
                PlanFeature(id: 12, description: "Premium support"),
                PlanFeature(
                    id: 15, description: "Exclusive community membership"),
              ],
            )
          ];

          selectedPlanIndex = 1; // Default to lifetime
        } catch (e) {
          NyLogger.error('Error setting up subscription plans: $e');
          showToastDanger(
              description: trans("Failed to load subscription plans"));
        } finally {
          setLoading(false, name: 'fetch_plans');
        }
      };

  Future<void> _validateCurrentSubscriptionStatus() async {
    if (course == null) return;

    try {
      Course updatedCourse =
          await CourseApiService().getCourseWithEnrollmentDetails(course!.id);
      if (mounted) {
        setState(() {
          course = updatedCourse;
        });

        if (updatedCourse.hasValidSubscription && !isRenewal) {
          _showAlreadyValidSubscriptionDialog();
          return;
        }
      }
    } catch (e) {
      NyLogger.error('Error validating subscription status: $e');
    }
  }

  Future<void> _fetchCurriculum() async {
    try {
      final courseApiService = CourseApiService();
      curriculumItems = await courseApiService.getCourseCurriculum(course!.id);
      curriculumItems.sort((a, b) => a['order'].compareTo(b['order']));
    } catch (e) {
      NyLogger.error('Error fetching curriculum: $e');
      curriculumItems = [];
    }
  }

  // void _forceResetPaymentState() {
  //   if (mounted) {
  //     setState(() {
  //       _isProcessingPayment = false;
  //       _paymentStartTime = null;
  //       _currentOrderDetails = null;
  //       _currentOrderId = null;
  //     });
  //     _paymentTimeoutTimer?.cancel();
  //   }
  // }

  String _getCurrentLoadingText() {
    if (_isCreatingOrder) return "Creating order...";
    if (_isProcessingPayment) return "Processing...";
    if (_isVerifyingPayment) return "Verifying...";
    if (_isCompletingEnrollment) return "Completing...";
    return "Loading...";
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isRenewal ? trans("Renew Subscription") : trans("Choose a Plan"),
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: afterLoad(
        child: () => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isRenewal)
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.all(16),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber, width: 1),
                  ),
                ),

              // Hero Image
              Container(
                height: 200,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: course!.image,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.grey[300],
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.grey[300],
                    child: Icon(Icons.image_not_supported,
                        color: Colors.white70, size: 50),
                  ),
                ),
              ),

              // Course Info
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course!.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      course!.smallDesc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      course!.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      course!.categoryName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Choose an Enrollment Plan',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Enrollment Plans
              ...subscriptionPlans.asMap().entries.map((entry) {
                int index = entry.key;
                SubscriptionPlan plan = entry.value;
                return _buildPlanCard(index, plan);
              }).toList(),

              SizedBox(height: 20),

              // Bottom Price and Enroll Now button
              Container(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      subscriptionPlans.isNotEmpty
                          ? "₹${subscriptionPlans[selectedPlanIndex].amount}"
                          : "",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildEnrollButton(), // ✅ Use new enhanced button
                  ],
                ),
              ),

              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(int index, SubscriptionPlan plan) {
    bool isSelected = selectedPlanIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedPlanIndex = index;
        });
      },
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFFEEEE13).withValues(alpha: isSelected ? 0.1 : 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Color(0xFFFFC940) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Color(0xFFFFC940) : Colors.grey[400]!,
                      width: 1,
                    ),
                    color: isSelected ? Color(0xFFFFC940) : Colors.white,
                  ),
                  child: isSelected
                      ? Icon(Icons.check, color: Colors.white, size: 14)
                      : SizedBox(),
                ),
                SizedBox(width: 12),
                Text(
                  plan.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8),
                if (plan.isPro)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFC940),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "PRO",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8),
                  Text(
                    "₹${plan.amount}",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  ...plan.features.map<Widget>((PlanFeature feature) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFFFFC940),
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${feature.description}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startPaymentProcess() async {
    if (subscriptionPlans.isEmpty ||
        selectedPlanIndex >= subscriptionPlans.length) {
      showToastDanger(description: trans("No plan selected"));
      return;
    }

    setState(() {
      _isCreatingOrder = true;
      _isProcessingPayment = false;
      _isVerifyingPayment = false;
      _isCompletingEnrollment = false;
      _currentLoadingMessage = "Creating payment order...";
      _paymentStartTime = DateTime.now();
    });
    // Set up timeout timer
    _paymentTimeoutTimer = Timer(Duration(minutes: 3), () {
      // Extended timeout
      if (_isAnyProcessActive && mounted) {
        _resetAllLoadingStates();
        showToastDanger(
            description: "Payment process timed out. Please try again.");
      }
    });

    SubscriptionPlan plan = subscriptionPlans[selectedPlanIndex];

    // Validate inputs before proceeding
    if (!_validatePaymentInputs(plan)) {
      _resetPaymentState();
      return;
    }

    try {
      // ✅ STEP 1: Create order with backend first
      NyLogger.info('🔄 Creating payment order...');
      showLoadingDialog(trans("Creating payment order..."));

      final courseApiService = CourseApiService();
      _currentOrderDetails = await courseApiService.createPaymentOrder(
        courseId: course!.id,
        planType: plan.planType,
        paymentCardId: null, // Add payment card support if needed
      );

      // Hide loading dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _currentOrderId = _currentOrderDetails!['order_id'];
      NyLogger.info('✅ Order created successfully: $_currentOrderId');

      // ✅ STEP 2: Initialize Razorpay with backend order details
      await _initializeRazorpayWithOrder(plan);
    } catch (e) {
      // Hide loading dialog if still showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _resetPaymentState();
      NyLogger.error('❌ Order creation failed: $e');

      String errorMessage = "Failed to create payment order";
      if (e.toString().contains('already enrolled') ||
          e.toString().contains('already have')) {
        errorMessage = "You are already enrolled in this course";
      } else if (e.toString().contains('Invalid plan')) {
        errorMessage = "Invalid subscription plan selected";
      } else if (e.toString().contains('not found')) {
        errorMessage = "Course not found. Please try again.";
      }

      showToastDanger(description: errorMessage);
    }
  }

  Future<void> _initializeRazorpayWithOrder(SubscriptionPlan plan) async {
    try {
      final userInfo = await _getUserInfo();

      var options = {
        'key': _currentOrderDetails!['key_id'],
        'order_id': _currentOrderDetails!['order_id'],
        'amount': _currentOrderDetails!['amount'] * 100,
        'currency': _currentOrderDetails!['currency'] ?? 'INR',
        'name': 'Course Enrollment',
        'description': 'Enrollment for ${course!.title}',
        'prefill': {
          'email': _currentOrderDetails!['user_info']['email'] ??
              userInfo['email'] ??
              '',
          'name': _currentOrderDetails!['user_info']['name'] ??
              userInfo['name'] ??
              '',
          'contact': _currentOrderDetails!['user_info']['contact'] ??
              userInfo['phone'] ??
              '',
        },
        'notes': _currentOrderDetails!['notes'] ??
            {
              'course_id': course!.id.toString(),
              'plan_type': plan.planType,
            },
        'theme': {
          'color': '#EFE458',
        }
      };

      NyLogger.debug('💳 Razorpay options: $options');
      NyLogger.info('🚀 Opening Razorpay payment interface...');

      // ✅ Update loading message before opening Razorpay
      if (mounted) {
        setState(() {
          _currentLoadingMessage = "Waiting for payment...";
        });
      }

      _razorpay.open(options);
    } catch (e) {
      _resetAllLoadingStates();
      NyLogger.error('❌ Razorpay initialization error: $e');
      showToastDanger(description: _getErrorMessage(e));
    }
  }

  void _resetPaymentState() {
    _paymentTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _isProcessingPayment = false;
        _paymentStartTime = null;
        _currentOrderDetails = null;
        _currentOrderId = null;
      });
    }
  }
  // void _startPaymentProcess() {
  //   if (subscriptionPlans.isEmpty ||
  //       selectedPlanIndex >= subscriptionPlans.length) {
  //     showToastDanger(description: trans("No plan selected"));
  //     return;
  //   }

  //   setState(() {
  //     _isProcessingPayment = true;
  //     _paymentStartTime = DateTime.now();
  //   });

  //   // Set up timeout timer
  //   _paymentTimeoutTimer = Timer(Duration(seconds: 60), () {
  //     if (_isProcessingPayment && mounted) {
  //       setState(() {
  //         _isProcessingPayment = false;
  //         _paymentStartTime = null;
  //       });
  //       showToastDanger(description: "Payment timed out. Please try again.");
  //     }
  //   });

  //   SubscriptionPlan plan = subscriptionPlans[selectedPlanIndex];

  //   // Validate inputs before proceeding
  //   if (!_validatePaymentInputs(plan)) {
  //     setState(() {
  //       _isProcessingPayment = false;
  //       _paymentStartTime = null;
  //     });
  //     _paymentTimeoutTimer?.cancel();
  //     return;
  //   }

  //   NyLogger.debug('Amount in paise: ${double.parse(plan.amount) * 100}');
  //   NyLogger.debug('Razorpay Key: ${getEnv('RAZORPAY_KEY_ID')}');

  //   _getUserInfo().then((userInfo) {
  //     var options = {
  //       'key': getEnv('RAZORPAY_KEY_ID'),
  //       'amount': (double.parse(plan.amount) * 100).toInt(),
  //       'name': 'Course Enrollment',
  //       'description': 'Enrollment for ${course!.title}',
  //       'prefill': {
  //         'email': userInfo['email'] ?? '',
  //         'name': userInfo['name'] ?? '',
  //         "contact": userInfo['phone'] ?? '',
  //       },
  //       'notes': {
  //         'course_id': course!.id.toString(),
  //         'plan_type': plan.planType,
  //       },
  //       'theme': {
  //         'color': '#EFE458',
  //       }
  //     };

  //     try {
  //       _razorpay.open(options);
  //     } catch (e) {
  //       _paymentTimeoutTimer?.cancel();
  //       setState(() {
  //         _isProcessingPayment = false;
  //         _paymentStartTime = null;
  //       });

  //       NyLogger.error('Razorpay open error: $e');

  //       if (e.toString().contains('is not a subtype of type')) {
  //         showToastDanger(
  //             description:
  //                 "Payment service temporarily unavailable. Please try again in a moment.");
  //       } else if (e.toString().contains('PlatformException')) {
  //         showToastDanger(
  //             description:
  //                 "Payment app not available. Please ensure you have a payment app installed.");
  //       } else {
  //         showToastDanger(
  //             description: "Payment initialization failed. Please try again.");
  //       }
  //     }
  //   }).catchError((e) {
  //     _paymentTimeoutTimer?.cancel();
  //     setState(() {
  //       _isProcessingPayment = false;
  //       _paymentStartTime = null;
  //     });
  //     showToastDanger(description: "Failed to get user info: ${e.toString()}");
  //     NyLogger.error('User info error: $e');
  //   });
  // }

  bool _validatePaymentInputs(SubscriptionPlan plan) {
    try {
      double amount = double.parse(plan.amount);
      if (amount <= 0) {
        showToastDanger(description: "Invalid plan amount");
        return false;
      }

      String razorpayKey = getEnv('RAZORPAY_KEY_ID');
      if (razorpayKey.isEmpty) {
        showToastDanger(description: "Payment configuration error");
        return false;
      }

      return true;
    } catch (e) {
      showToastDanger(description: "Invalid plan configuration");
      return false;
    }
  }

  Future<Map<String, dynamic>> _getUserInfo() async {
    try {
      final userData = await Auth.data();
      return {
        'name': userData['full_name'] ?? '',
        'email': userData['email'] ?? '',
        'phone': userData['phone_number'] ?? '',
      };
    } catch (e) {
      return {};
    }
  }

  String generateUniqueId() {
    var uuid = Uuid();
    return uuid.v1();
  }

  void _showAlreadyValidSubscriptionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(trans("Active Subscription Found")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trans(
                  "You already have an active subscription to this course.")),
              SizedBox(height: 8),
              Text(
                trans("Plan: ${course!.subscriptionPlanName}"),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (!course!.isLifetimeSubscription &&
                  course!.subscriptionExpiryDate != null)
                Text(
                  trans(
                      "Expires: ${course!.subscriptionExpiryDate!.day}/${course!.subscriptionExpiryDate!.month}/${course!.subscriptionExpiryDate!.year}"),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              if (course!.isLifetimeSubscription)
                Text(
                  trans("Lifetime Access"),
                  style: TextStyle(fontSize: 12, color: Colors.green[600]),
                ),
            ],
          ),
          actions: [
            TextButton(
              child: Text(trans("Go Back")),
              onPressed: () {
                Navigator.pop(context);
                pop(); // Close enrollment page
              },
            ),
            TextButton(
              child: Text(trans("View Course")),
              style: TextButton.styleFrom(foregroundColor: Colors.amber),
              onPressed: () {
                Navigator.pop(context);
                routeTo(CourseCurriculumPage.path, data: {
                  'course': course!,
                  'curriculum': curriculumItems,
                });
              },
            ),
          ],
        );
      },
    );
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    NyLogger.debug('Payment Success Response: ${response.toString()}');
    NyLogger.debug('Payment Success Response: ${response.orderId}');
    NyLogger.debug('Payment Success Response: ${response.paymentId}');
    NyLogger.debug('Payment Success Response: ${response.signature}');

    // Cancel timeout and reset state immediately
    _paymentTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _isProcessingPayment = false;
        _isVerifyingPayment = true;
        _currentLoadingMessage =
            "Payment successful! Verifying and processing enrollment...";
      });
    }

    try {
      String paymentId = response.paymentId ?? '';
      String orderId = response.orderId ?? _currentOrderId ?? '';
      String signature = response.signature ?? '';

      if (paymentId.isEmpty || orderId.isEmpty) {
        throw Exception(
            "Invalid payment response - missing required information");
      }

      // ✅ Update loading message for verification step
      if (mounted) {
        setState(() {
          _currentLoadingMessage = "Verifying payment with our servers...";
        });
      }

      SubscriptionPlan plan = subscriptionPlans[selectedPlanIndex];
      var courseApiService = CourseApiService();

      // Add small delay to show the verification message
      await Future.delayed(Duration(milliseconds: 800));

      // Verify payment with backend
      final purchaseResult = await courseApiService.purchaseCourse(
        courseId: course!.id,
        planType: plan.planType,
        razorpayPaymentId: paymentId,
        razorpayOrderId: orderId,
        razorpaySignature: signature,
      );

      NyLogger.info('✅ Payment verification successful');

      // ✅ Transition to enrollment completion phase
      if (mounted) {
        setState(() {
          _isVerifyingPayment = false;
          _isCompletingEnrollment = true;
          _currentLoadingMessage = "Finalizing your enrollment...";
        });
      }

      await _handleSuccessfulEnrollment(
          courseApiService, paymentId, purchaseResult);
    } catch (e) {
      _resetAllLoadingStates();
      NyLogger.error('❌ Payment verification failed: $e');

      String errorMessage = _getPaymentErrorMessage(e);
      showToastDanger(description: errorMessage);
    }
  }

  String _getPaymentErrorMessage(dynamic error) {
    String errorStr = error.toString().toLowerCase();

    if (errorStr.contains('signature')) {
      return "Payment verification failed. Please contact support with your transaction details.";
    } else if (errorStr.contains('already enrolled')) {
      return "You are already enrolled in this course";
    } else if (errorStr.contains('amount mismatch')) {
      return "Payment amount verification failed. Please contact support.";
    } else if (errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return "Network error during verification. Please check your connection.";
    } else {
      return "Payment verification failed. Please try again or contact support.";
    }
  }

  String _getPaymentFailureMessage(PaymentFailureResponse response) {
    if (response.code != null) {
      switch (response.code) {
        case 'BAD_REQUEST_ERROR':
          return 'Invalid payment request. Please try again.';
        case 'GATEWAY_ERROR':
          return 'Payment gateway error. Please try again.';
        case 'NETWORK_ERROR':
          return 'Network error. Please check your connection and try again.';
        case 'SERVER_ERROR':
          return 'Server error. Please try again later.';
        default:
          return response.message ?? 'Payment failed. Please try again.';
      }
    }
    return response.message ?? 'Payment failed. Please try again.';
  }

  Widget _buildEnrollButton() {
    return Container(
      width: 150,
      height: 50,
      child: ElevatedButton(
        onPressed: _isAnyProcessActive ? null : _startPaymentProcess,
        onLongPress: _isAnyProcessActive ? _forceResetPaymentState : null,
        child: _isAnyProcessActive
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _getCurrentLoadingText(),
                    style: TextStyle(fontSize: 8, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  if (_isAnyProcessActive)
                    Text(
                      'Hold to cancel',
                      style: TextStyle(fontSize: 6, color: Colors.grey[400]),
                    ),
                ],
              )
            : Text(
                'Enroll Now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFFEFE458),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSuccessfulEnrollment(CourseApiService courseApiService,
      String paymentId, dynamic purchaseResult) async {
    try {
      // ✅ Update loading message for cache invalidation
      if (mounted) {
        setState(() {
          _currentLoadingMessage = "Updating your course access...";
        });
      }

      await courseApiService.invalidateEnrollmentCaches();
      await Future.delayed(Duration(milliseconds: 500)); // Show the message

      // ✅ Update loading message for course data fetch
      if (mounted) {
        setState(() {
          _currentLoadingMessage = "Preparing your course content...";
        });
      }

      Course updatedCourse;
      try {
        updatedCourse = await courseApiService
            .getCourseWithEnrollmentDetails(course!.id, refresh: true);
        NyLogger.info('✅ Retrieved updated course with enrollment details');
      } catch (e) {
        updatedCourse = _createUpdatedCourse();
      }

      // ✅ Update loading message for final steps
      if (mounted) {
        setState(() {
          _currentLoadingMessage = "Setting up offline downloads...";
        });
      }

      // Notify other screens
      _notifyEnrollmentSuccess(updatedCourse);

      // Start background download
      _startBackgroundDownload();

      await Future.delayed(Duration(milliseconds: 500)); // Show final message

      // ✅ ONLY NOW stop all loading
      _resetAllLoadingStates();
      _paymentTimeoutTimer?.cancel();

      // Show success dialog
      await _showSuccessDialog(paymentId, updatedCourse, purchaseResult);
    } catch (e) {
      _resetAllLoadingStates();
      throw Exception("Failed to complete enrollment: ${e.toString()}");
    }
  }

  Course _createUpdatedCourse() {
    return Course(
      id: course!.id,
      title: course!.title,
      image: course!.image,
      description: course!.description,
      smallDesc: course!.smallDesc,
      category: course!.category,
      categoryName: course!.categoryName,
      location: course!.location,
      priceOneMonth: course!.priceOneMonth,
      priceThreeMonths: course!.priceThreeMonths,
      priceLifetime: course!.priceLifetime,
      isFeatured: course!.isFeatured,
      dateUploaded: course!.dateUploaded,
      enrolledStudents: course!.enrolledStudents,
      isEnrolled: true, // This is the key change
      isWishlisted: course!.isWishlisted,
      objectives: course!.objectives,
      requirements: course!.requirements,
      curriculum: course!.curriculum,
    );
  }

  void _notifyEnrollmentSuccess(Course updatedCourse) {
    final updateData = {
      'type': 'course_enrolled',
      'courseId': course!.id,
      'updatedCourse': updatedCourse.toJson(),
      'enrollmentSuccess': true,
    };

    updateState('/search_tab', data: updateData);
    updateState('/home_tab', data: updateData);
    updateState('/course-detail', data: updateData);
    updateState('/wishlist_tab', data: updateData);
  }

  void _startBackgroundDownload() {
    Future.microtask(() async {
      try {
        if (curriculumItems.isNotEmpty && username != null && email != null) {
          bool downloadStarted = await _videoService.downloadAllVideos(
            courseId: course!.id.toString(),
            course: course!,
            curriculum: curriculumItems,
            watermarkText: username!,
            email: email!,
          );

          if (downloadStarted && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(trans(
                    "Videos are queued for download. You can continue using the app while downloads complete in the background.")),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (e) {
        NyLogger.error('Error starting background download: $e');
      }
    });
  }

  Future<void> _showSuccessDialog(
      String paymentId, Course updatedCourse, dynamic purchaseResult) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("🎉 Enrollment Successful"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 60,
              ),
              SizedBox(height: 16),
              Text(
                "You have successfully enrolled in ${course!.title}.",
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                "Payment ID: ${paymentId}",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (_currentOrderId != null) ...[
                SizedBox(height: 4),
                Text(
                  "Order ID: ${_currentOrderId}",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
              SizedBox(height: 8),
              Text(
                "Your videos are being prepared for offline viewing.",
                style: TextStyle(fontSize: 12, color: Colors.blue[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text("View Course"),
              style: TextButton.styleFrom(foregroundColor: Colors.amber),
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _navigateToBase(updatedCourse);
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateToBase(Course updatedCourse) {
    routeTo(BaseNavigationHub.path,
        tabIndex: 1,
        navigationType: NavigationType.pushAndRemoveUntil,
        removeUntilPredicate: (route) => true);

    // Force refresh the current CourseDetailPage with updated course
    updateState('/course-detail', data: {
      'refresh': true,
      'course': updatedCourse,
      'curriculum': curriculumItems,
    });
  }

  void _clearPaymentData() {
    // Clear any cached payment information
    // Reset form state if needed
  }

  void _showPaymentErrorDialog(String errorMessage) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Payment Failed"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(errorMessage),
            SizedBox(height: 8),
            Text(
              "Please try again or contact support if the problem persists.",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Retry payment
              _startPaymentProcess();
            },
            child: Text("Retry"),
          ),
        ],
      ),
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    NyLogger.error('❌ Payment Error Response: ${response.toString()}');

    if (!mounted) return;

    // ✅ Stop all loading on error
    _resetAllLoadingStates();
    _clearPaymentData();

    try {
      String errorMessage = _getPaymentFailureMessage(response);
      _showPaymentErrorDialog(errorMessage);
    } catch (e) {
      NyLogger.error('Error handling payment failure: $e');
      _showPaymentErrorDialog("Payment failed. Please try again.");
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    try {
      // Cancel timeout and reset state
      _paymentTimeoutTimer?.cancel();

      _resetAllLoadingStates();
      String walletName = response.walletName ?? 'External Wallet';
      showToastInfo(description: "External wallet selected: $walletName");
    } catch (e) {
      _resetAllLoadingStates();
      NyLogger.error('Error handling external wallet: $e');
      showToastInfo(description: "External wallet selected");
    }
  }

  void _resetAllLoadingStates() {
    _paymentTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _isCreatingOrder = false;
        _isProcessingPayment = false;
        _isVerifyingPayment = false;
        _isCompletingEnrollment = false;
        _currentLoadingMessage = "";
        _paymentStartTime = null;
        _currentOrderDetails = null;
        _currentOrderId = null;
      });
    }
  }

  // ✅ NEW: Force reset (for long press)
  void _forceResetPaymentState() {
    _resetAllLoadingStates();
    showToastInfo(description: "Payment process cancelled");
  }

  // ✅ NEW: Better error message handling
  String _getErrorMessage(dynamic error) {
    String errorStr = error.toString().toLowerCase();

    if (errorStr.contains('already enrolled') ||
        errorStr.contains('already have')) {
      return "You are already enrolled in this course";
    } else if (errorStr.contains('invalid plan')) {
      return "Invalid subscription plan selected";
    } else if (errorStr.contains('not found')) {
      return "Course not found. Please try again.";
    } else if (errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return "Network error. Please check your connection and try again.";
    } else if (errorStr.contains('timeout')) {
      return "Request timed out. Please try again.";
    } else {
      return "Failed to create payment order. Please try again.";
    }
  }

  void showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(
                color: Colors.amber,
              ),
              SizedBox(width: 20),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
        );
      },
    );
  }
}
