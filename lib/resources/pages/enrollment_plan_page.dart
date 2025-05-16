import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../app/models/course.dart';
import '../../app/models/enrollment.dart';
import '../../app/networking/course_api_service.dart';
import '../../app/networking/purchase_api_service.dart';
import '../../utils/enrollment_data.dart';

class EnrollmentPlanPage extends NyStatefulWidget {
  static RouteView path = ("/enrollment-plan", (_) => EnrollmentPlanPage());

  EnrollmentPlanPage({super.key})
      : super(child: () => _EnrollmentPlanPageState());
}

class _EnrollmentPlanPageState extends NyPage<EnrollmentPlanPage> {
  Course? course;
  int selectedPlanIndex = 0; // Default to first plan (PRO)
  List<SubscriptionPlan> subscriptionPlans = [];
  bool _isProcessingPayment = false;

  // Initialize Razorpay
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();

    // Initialize Razorpay
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    // Clean up Razorpay
    _razorpay.clear();
    super.dispose();
  }

  @override
  get init => () async {
        setLoading(true, name: 'fetch_plans');

        // Get course data from previous page
        Map<String, dynamic> data = widget.data();
        if (data.containsKey('course') && data['course'] != null) {
          course = data['course'];
        } else {
          // Handle missing course data
          showToastWarning(description: trans("Course information is missing"));
          pop();
          return;
        }
        try {
          var purchaseApiService = PurchaseApiService();
          var plansData = await purchaseApiService.getSubscriptionPlans();

          // Convert to model objects
          subscriptionPlans = plansData
              .map<SubscriptionPlan>((data) => SubscriptionPlan.fromJson(data))
              .toList();

          // Sort plans - put pro plans first
          subscriptionPlans.sort((a, b) => b.isPro ? 1 : -1);

          // Set default selection to first Pro plan if available
          int proIndex = subscriptionPlans.indexWhere((plan) => plan.isPro);
          if (proIndex != -1) {
            selectedPlanIndex = proIndex;
          }
        } catch (e) {
          NyLogger.error('Error fetching subscription plans: $e');
          showToastDanger(
              description: trans("Failed to load subscription plans"));
        } finally {
          setLoading(false, name: 'fetch_plans');
        }
      };

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
          trans("Choose a Plan"),
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
              // Hero Image
              Container(
                height: 200,
                width: double.infinity,
                color: Color(0xFF8CD057), // Green color
                child: Stack(
                  children: [
                    Positioned(
                        right: 0,
                        child: CachedNetworkImage(
                          imageUrl: course?.image ?? '',
                          height: 200,
                          width: 200,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            height: 200,
                            width: 200,
                            color: Colors.grey[300],
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 200,
                            width: 200,
                            color: Colors.grey[300],
                            child: Icon(Icons.image_not_supported,
                                color: Colors.white),
                          ),
                        )),
                  ],
                ),
              ),

              // Course Title and Description
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
                    Container(
                      width: 150,
                      height: 50,
                      child: ElevatedButton(
                        // style:ButtonStyle),
                        onPressed:
                            _isProcessingPayment ? null : _startPaymentProcess,
                        child: _isProcessingPayment
                            ? CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.amber),
                                strokeWidth: 3,
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
                          backgroundColor: Color(0xFFEFE458), // Yellow
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom padding for safety
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
            // Row with check circle and title/badge only
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Selection circle
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
                // Title and badge in the same row
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
                      plan.isPro ? "PRO" : "",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),

            // Price and features aligned with title (not with check circle)
            Padding(
              padding: const EdgeInsets.only(left: 32), // Align with title text
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8),
                  // Price
                  Text(
                    "₹${plan.amount}",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),

                  // Features
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

  void _startPaymentProcess() {
    if (subscriptionPlans.isEmpty ||
        selectedPlanIndex >= subscriptionPlans.length) {
      showToastDanger(description: trans("No plan selected"));
      return;
    }

    setState(() {
      _isProcessingPayment = true;
    });

    // Get selected plan
    SubscriptionPlan plan = subscriptionPlans[selectedPlanIndex];
    print(double.parse(plan.amount) * 100);
    print(getEnv('RAZORPAY_KEY_ID'));

    // Get user info
    _getUserInfo().then((userInfo) {
      // Create Razorpay options
      var options = {
        'key': "rzp_test_jVs3DvUw9Q14gj",
        'amount': (double.parse(plan.amount) * 100)
            .toString(), // Razorpay expects amount in paise
        'name': 'Course Enrollment',
        'description': 'Enrollment for ${course!.title}',
        'prefill': {
          'email': userInfo['email'] ?? '',
          'name': userInfo['name'] ?? '',
          "contact": userInfo['phone'] ?? '',
        },
        'notes': {
          'course_id': course!.id.toString(),
          'plan_id': plan.id.toString(),
        },
        'theme': {
          'color': '#EFE458', // Yellow color
        }
      };

      try {
        _razorpay.open(options);
      } catch (e) {
        setState(() {
          _isProcessingPayment = false;
        });
        showToastDanger(
            description: "Payment initialization failed: ${e.toString()}");
      }
    }).catchError((e) {
      setState(() {
        _isProcessingPayment = false;
      });
      showToastDanger(description: "Failed to get user info: ${e.toString()}");
    });
  }

  // Get user info for Razorpay prefill
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

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    print(response);
    // Get payment details from Razorpay response

    String paymentId = response.paymentId ?? '';
    String orderId = response.orderId ?? '';
    String signature = response.signature ?? "";
    print(paymentId);
    print(orderId);
    print(signature);

    try {
      // Show processing dialog
      showLoadingDialog(trans("Processing enrollment..."));

      // Get selected plan
      SubscriptionPlan plan = subscriptionPlans[selectedPlanIndex];

      // Create enrollment with the payment reference code
      var courseApiService = CourseApiService();
      await courseApiService.purchaseCourse(
          courseId: course!.id,
          planId: plan.id,
          razorpayPaymentId: paymentId,
          razorpayOrderId: orderId,
          razorpaySignature: signature);

      // Hide processing dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Notify other screens about the enrollment
      updateState('/search_tab', data: "refresh_courses");
      updateState('/home_tab', data: "refresh_enrollments");

      // Show success dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Enrollment Successful"),
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
                  "Transaction ID: ${paymentId}",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text("View Course"),
                onPressed: () {
                  // Navigate to home tab with index 3
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  updateState('/app_layout', data: {"index": 3});
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      // Hide processing dialog if showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error message
      showToastDanger(description: "Enrollment failed: ${e.toString()}");
    } finally {
      setState(() {
        _isProcessingPayment = false;
      });
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    setState(() {
      _isProcessingPayment = false;
    });

    // Show error message
    showToastDanger(
        description: "Payment failed: ${response.message ?? 'Unknown error'}");
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() {
      _isProcessingPayment = false;
    });

    // Show info message
    showToastInfo(
        description: "External wallet selected: ${response.walletName ?? ''}");
  }

  // Helper to show loading dialog
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
              Text(message),
            ],
          ),
        );
      },
    );
  }
}
