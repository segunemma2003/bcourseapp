import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/course_detail_page.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/purchase_history.dart';
import '../../app/networking/purchase_api_service.dart';

class PurchaseHistoryPage extends NyStatefulWidget {
  static RouteView path = ("/purchase-history", (_) => PurchaseHistoryPage());

  PurchaseHistoryPage({super.key})
      : super(child: () => _PurchaseHistoryPageState());
}

class _PurchaseHistoryPageState extends NyPage<PurchaseHistoryPage> {
  List<PurchaseHistory> _purchaseHistory = [];
  bool _isAuthenticated = false;

  @override
  LoadingStyle get loadingStyle => LoadingStyle.skeletonizer(
        child: _buildSkeletonLayout(),
      );

  @override
  get init => () async {
        super.init();

        // Check authentication status
        _isAuthenticated = await Auth.isAuthenticated();
        if (!_isAuthenticated) {
          // Redirect to login if not authenticated
          await routeTo(SigninPage.path);
          return;
        }

        // Initialize data
        await _fetchPurchaseHistory();
      };

  // Define state actions that can be called from other widgets
  @override
  get stateActions => {
        "refresh_purchase_history": () async {
          await _fetchPurchaseHistory(refresh: true);
        },
        "update_auth_status": (bool status) async {
          setState(() {
            _isAuthenticated = status;
          });
          if (_isAuthenticated) {
            await _fetchPurchaseHistory(refresh: true);
          }
        },
      };

  Future<void> _fetchPurchaseHistory({bool refresh = false}) async {
    // Use Nylo's loading state management with skeletonizer
    setLoading(true, name: 'fetch_purchase_history');

    try {
      // Use the PurchaseApiService
      var purchaseApiService = PurchaseApiService();

      // Fetch purchase history data
      List<dynamic> purchaseData = [];

      try {
        // Get purchase history from API
        purchaseData =
            await purchaseApiService.getPurchaseHistory(refresh: refresh);
      } catch (e) {
        // Handle error
        NyLogger.error('Error fetching purchase history: $e');
        throw e;
      }

      // Parse data into model
      _purchaseHistory =
          purchaseData.map((data) => PurchaseHistory.fromJson(data)).toList();

      // Optional: Store in local storage for offline access
      await storageSave(PurchaseHistory.key, purchaseData);
    } catch (e) {
      NyLogger.error('Error fetching purchase history: $e');

      // Try to load from local storage as fallback
      try {
        final cachedData = await storageRead(PurchaseHistory.key);
        if (cachedData != null) {
          _purchaseHistory =
              cachedData.map((data) => PurchaseHistory.fromJson(data)).toList();
        } else {
          _purchaseHistory = [];
        }
      } catch (_) {
        _purchaseHistory = [];
      }

      // Show error using Nylo toast
      showToast(
          title: trans("Error"),
          description: trans(
              "Failed to load purchase history from server, showing cached data"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.warning);
    } finally {
      // Complete loading
      setLoading(false, name: 'fetch_purchase_history');
    }
  }

  void _viewCourseDetails(int courseId) {
    // Navigate to course details page
    routeTo(CourseDetailPage.path, data: {'courseId': courseId});
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              trans("Purchase History"),
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: afterLoad(
        loadingKey: 'fetch_purchase_history',
        child: () => _purchaseHistory.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
                padding: EdgeInsets.only(top: 12),
                itemCount: _purchaseHistory.length,
                itemBuilder: (context, index) {
                  final purchase = _purchaseHistory[index];
                  return _buildPurchaseItem(purchase);
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 24),
          Text(
            trans("No Purchase History"),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            trans("You haven't purchased any courses yet"),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseItem(PurchaseHistory purchase) {
    final bool isActive = purchase.payment_status == 'Completed';
    final String formattedPurchaseDate =
        "${purchase.purchase_date.day}/${purchase.purchase_date.month}/${purchase.purchase_date.year}";

    // Calculate expiry date (simulate as 1 year from purchase)
    final DateTime expiryDate = purchase.purchase_date.add(Duration(days: 365));
    final String formattedExpiryDate =
        "${expiryDate.day}/${expiryDate.month}/${expiryDate.year}";

    return Container(
      margin: EdgeInsets.only(bottom: 12, left: 16, right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 0,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _viewCourseDetails(purchase.course),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Course Image
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              child: purchase.course_image != null
                  ? Image.network(
                      purchase.course_image!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 100,
                          height: 100,
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.grey.shade400,
                          ),
                        );
                      },
                    )
                  : Container(
                      width: 100,
                      height: 100,
                      color: Colors.grey.shade200,
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey.shade400,
                      ),
                    ),
            ),

            // Course Details
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Course Title
                    Text(
                      purchase.course_title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: 4),

                    // Payment Details
                    Text(
                      trans("Amount") + ": " + purchase.amount,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: 4),

                    // Card Details
                    Text(
                      trans("Card") + ": ****" + purchase.card_last_four,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),

                    SizedBox(height: 8),

                    // Status Badge
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.amber : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isActive
                            ? trans("Active") + " • " + formattedPurchaseDate
                            : trans("Expired") + ": " + formattedExpiryDate,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isActive ? Colors.black : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            margin: EdgeInsets.only(bottom: 16),
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 100,
                  color: Colors.grey.shade300,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Container(
                          height: 16,
                          width: double.infinity,
                          color: Colors.grey.shade300,
                        ),
                        Container(
                          height: 12,
                          width: 200,
                          color: Colors.grey.shade300,
                        ),
                        Container(
                          height: 12,
                          width: 150,
                          color: Colors.grey.shade300,
                        ),
                        Container(
                          height: 24,
                          width: 100,
                          color: Colors.grey.shade300,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
