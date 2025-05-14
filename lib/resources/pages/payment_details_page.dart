import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/resources/pages/signin_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/payment_card.dart';
import '../../app/networking/purchase_api_service.dart';
import '../widgets/add_card_modal_widget.dart';

class PaymentDetailsPage extends NyStatefulWidget {
  static RouteView path = ("/payment-details", (_) => PaymentDetailsPage());

  PaymentDetailsPage({super.key})
      : super(child: () => _PaymentDetailsPageState());
}

class _PaymentDetailsPageState extends NyPage<PaymentDetailsPage> {
  List<dynamic> _paymentMethods = [];
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
        await _fetchPaymentMethods();
      };

  @override
  get stateActions => {
        "refresh_payment_methods": () async {
          await _fetchPaymentMethods(refresh: true);
        },
        "update_auth_status": (bool status) async {
          setState(() {
            _isAuthenticated = status;
          });
          if (_isAuthenticated) {
            await _fetchPaymentMethods(refresh: true);
          }
        },
      };

  Future<void> _fetchPaymentMethods({bool refresh = false}) async {
    setLoading(true, name: 'fetch_payment_methods');

    try {
      var purchaseApiService = PurchaseApiService();
      _paymentMethods =
          await purchaseApiService.getPaymentCards(refresh: refresh);
    } catch (e) {
      NyLogger.error('Failed to fetch payment methods: $e');

      try {
        final cachedData = await storageRead('payment_cards');
        if (cachedData != null) {
          _paymentMethods = cachedData;
        } else {
          _paymentMethods = [];
        }
      } catch (_) {
        _paymentMethods = [];
      }

      showToast(
        title: trans("Error"),
        description: trans("Failed to load your payment methods"),
        icon: Icons.error_outline,
        style: ToastNotificationStyleType.danger,
      );
    } finally {
      setLoading(false, name: 'fetch_payment_methods');
    }
  }

  void _addNewCard() {
    // Show the card addition modal
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Full height for keyboard
      backgroundColor: Colors.transparent,
      builder: (context) => AddCardModal(
        onCardAdded: () {
          // Refresh the payment methods list after adding a card
          _fetchPaymentMethods(refresh: true);
        },
      ),
    );
  }

  void _deleteCard(int cardId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(trans("Remove Card")),
        content: Text(trans("Are you sure you want to remove this card?")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(trans("Cancel")),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteCard(cardId);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text(trans("Remove")),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCard(int cardId) async {
    setLoading(true, name: 'delete_card');

    try {
      var purchaseApiService = PurchaseApiService();
      await purchaseApiService.deletePaymentCard(cardId);
      await _fetchPaymentMethods(refresh: true);

      showToast(
        title: trans("Success"),
        description: trans("Card removed successfully"),
        icon: Icons.check_circle,
        style: ToastNotificationStyleType.success,
      );
    } catch (e) {
      NyLogger.error('Failed to delete card: $e');
      showToast(
        title: trans("Error"),
        description: trans("Failed to remove card"),
        icon: Icons.error_outline,
        style: ToastNotificationStyleType.danger,
      );
    } finally {
      setLoading(false, name: 'delete_card');
    }
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
                color: Colors.grey.withValues(alpha: .3),
                spreadRadius: 1,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: AppBar(
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              trans("Payment Details"),
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
        loadingKey: 'fetch_payment_methods',
        child: () => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_paymentMethods.isEmpty)
                _buildEmptyState()
              else
                ..._paymentMethods
                    .map((method) => _buildPaymentMethodItem(method))
                    .toList(),
              _buildAddCardButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: .1),
            spreadRadius: 0,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.credit_card_off,
              size: 60,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 16),
            Text(
              trans("No Payment Methods"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              trans("You haven't added any payment methods yet"),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodItem(Map<String, dynamic> method) {
    // Convert map to PaymentCard model
    PaymentCard card = PaymentCard.fromJson(method);

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: .1),
            spreadRadius: 0,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "${_getCardTypeLabel(card.cardType)} ****${card.lastFour}",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (card.isDefault)
                    Container(
                      margin: EdgeInsets.only(left: 8),
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        trans("Default"),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                "Exp: ${card.expiryMonth}/${card.expiryYear}",
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildCardLogoImage(card.cardType),
              SizedBox(width: 16),
              InkWell(
                onTap: () => _deleteCard(card.id!),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delete,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardLogoImage(String cardType) {
    String imageUrl;

    switch (cardType.toLowerCase()) {
      case 'visa':
        imageUrl =
            "https://cdn.jsdelivr.net/gh/creativetimofficial/public-assets@master/soft-ui-design-system/assets/img/logos/visa.png";
        break;
      case 'mastercard':
        imageUrl =
            "https://cdn.jsdelivr.net/gh/creativetimofficial/public-assets@master/soft-ui-design-system/assets/img/logos/mastercard.png";
        break;
      case 'amex':
        imageUrl =
            "https://cdn.jsdelivr.net/gh/creativetimofficial/public-assets@master/soft-ui-design-system/assets/img/logos/americanexpress.png";
        break;
      case 'discover':
        imageUrl =
            "https://cdn.jsdelivr.net/gh/creativetimofficial/public-assets@master/soft-ui-design-system/assets/img/logos/discover.png";
        break;
      case 'verve':
        imageUrl =
            "https://upload.wikimedia.org/wikipedia/commons/4/40/Verve_logo.png";
        break;
      default:
        return Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              cardType.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
    }

    return Image.network(
      imageUrl,
      width: 40,
      height: 24,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              cardType.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddCardButton() {
    return InkWell(
      onTap: _addNewCard,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: .1),
              spreadRadius: 0,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.credit_card_outlined,
                color: Colors.black,
                size: 20,
              ),
            ),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trans("Add new card"),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  trans("Add new credit/debit card"),
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            Spacer(),
            Icon(
              Icons.arrow_forward,
              color: Colors.grey,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _getCardTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'visa':
        return 'Visa';
      case 'mastercard':
        return 'Mastercard';
      case 'amex':
        return 'American Express';
      case 'discover':
        return 'Discover';
      case 'verve':
        return 'Verve';
      default:
        return 'Card';
    }
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
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            margin: EdgeInsets.only(bottom: 16),
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Container(
                          height: 16,
                          width: 150,
                          color: Colors.grey.shade300,
                        ),
                        Container(
                          height: 12,
                          width: 100,
                          color: Colors.grey.shade300,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 40,
                  height: 24,
                  margin: EdgeInsets.only(right: 16),
                  color: Colors.grey.shade300,
                ),
                Container(
                  width: 24,
                  height: 24,
                  margin: EdgeInsets.only(right: 16),
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
