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

  @override
  void initState() {
    super.initState();

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
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
                    Container(
                      width: 150,
                      height: 50,
                      child: ElevatedButton(
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
                          backgroundColor: Color(0xFFEFE458),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                      ),
                    ),
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

  void _startPaymentProcess() {
    if (subscriptionPlans.isEmpty ||
        selectedPlanIndex >= subscriptionPlans.length) {
      showToastDanger(description: trans("No plan selected"));
      return;
    }

    setState(() {
      _isProcessingPayment = true;
    });

    SubscriptionPlan plan = subscriptionPlans[selectedPlanIndex];
    NyLogger.debug('Amount in paise: ${double.parse(plan.amount) * 100}');
    NyLogger.debug('Razorpay Key: ${getEnv('RAZORPAY_KEY_ID')}');

    _getUserInfo().then((userInfo) {
      var options = {
        'key': getEnv('RAZORPAY_KEY_ID'),
        'amount': (double.parse(plan.amount) * 100).toString(),
        'name': 'Course Enrollment',
        'description': 'Enrollment for ${course!.title}',
        'prefill': {
          'email': userInfo['email'] ?? '',
          'name': userInfo['name'] ?? '',
          "contact": userInfo['phone'] ?? '',
        },
        'notes': {
          'course_id': course!.id.toString(),
          'plan_type': plan.planType,
        },
        'theme': {
          'color': '#EFE458',
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
    NyLogger.debug('Payment Success Response: $response');

    String paymentId = response.paymentId ?? '';
    String orderId = response.orderId ?? (await generateUniqueId());
    String signature = response.signature ?? (await generateUniqueId());

    try {
      showLoadingDialog(trans("Processing enrollment..."));

      SubscriptionPlan plan = subscriptionPlans[selectedPlanIndex];
      var courseApiService = CourseApiService();

      await courseApiService.purchaseCourse(
        courseId: course!.id,
        planType: plan.planType,
        razorpayPaymentId: paymentId,
        razorpayOrderId: orderId,
        razorpaySignature: signature,
      );

      // Hide processing dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      await courseApiService.invalidateEnrollmentCaches();

// Get updated course with fresh enrollment details
      Course updatedCourse;
      try {
        updatedCourse =
            await courseApiService.getCourseWithEnrollmentDetails(course!.id);
      } catch (e) {
        // Fallback: create updated course manually
        updatedCourse = Course(
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

      // Notify other screens about the enrollment
      updateState('/search_tab', data: "refresh_courses");
      updateState('/home_tab', data: "refresh_enrollments");

      // Start automatic background download
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

      // Create updated course with enrollment status
      updatedCourse = Course(
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

      // Show success dialog with navigation back to CourseDetailPage
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
                SizedBox(height: 8),
                Text(
                  "Your videos are being prepared for offline viewing.",
                  style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text("View Course Details"),
                onPressed: () {
                  Navigator.pop(context); // Close dialog

                  // Navigate back to CourseDetailPage with updated course data

                  routeTo(BaseNavigationHub.path,
                      tabIndex: 1,
                      navigationType: NavigationType.pushAndRemoveUntil,
                      removeUntilPredicate: (route) => true);

                  // Force refresh the current CourseDetailPage with updated course
                  updateState('/course-detail', data: {
                    'refresh': true,
                    'course': updatedCourse, // Pass the updated course
                    'curriculum': curriculumItems,
                  });
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      showToastDanger(description: "Enrollment failed: ${e.toString()}");
    } finally {
      setState(() {
        _isProcessingPayment = false;
      });
    }
  }

  void _clearPaymentData() {
    // Clear any cached payment information
    // Reset form state if needed
  }
  void _showPaymentErrorDialog(PaymentFailureResponse response) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Payment Failed"),
        content: Text(
            "Please try again or contact support if the problem persists."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() {
        _isProcessingPayment = false;
      });

      // Clear any sensitive payment data
      _clearPaymentData();

      // Show user-friendly error message
      _showPaymentErrorDialog(response);
    }

    showToastDanger(
        description: "Payment failed: ${response.message ?? 'Unknown error'}");
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() {
      _isProcessingPayment = false;
    });

    showToastInfo(
        description: "External wallet selected: ${response.walletName ?? ''}");
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
              Text(message),
            ],
          ),
        );
      },
    );
  }
}
