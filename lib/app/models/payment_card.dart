import 'package:nylo_framework/nylo_framework.dart';

class PaymentCard extends Model {
  final int? id;
  final String cardType;
  final String lastFour;
  final String cardHolderName;
  final String expiryMonth;
  final String expiryYear;
  final bool isDefault;

  // These fields are used for form input but not stored in the backend
  String? cardNumber;
  String? cvv;

  static StorageKey key = "payment_card";

  PaymentCard({
    this.id,
    required this.cardType,
    required this.lastFour,
    required this.cardHolderName,
    required this.expiryMonth,
    required this.expiryYear,
    this.isDefault = false,
    this.cardNumber,
    this.cvv,
  }) : super(key: key);

  PaymentCard.fromJson(Map<String, dynamic> data)
      : id = data['id'],
        cardType = data['card_type'] ?? '',
        lastFour = data['last_four'] ?? '',
        cardHolderName = data['card_holder_name'] ?? '',
        expiryMonth = data['expiry_month'] ?? '',
        expiryYear = data['expiry_year'] ?? '',
        isDefault = data['is_default'] ?? false,
        cardNumber = null, // Not stored in backend
        cvv = null, // Not stored in backend
        super(key: key);

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'card_type': cardType,
      'last_four': lastFour,
      'card_holder_name': cardHolderName,
      'expiry_month': expiryMonth,
      'expiry_year': expiryYear,
      'is_default': isDefault,
      // Don't include cardNumber and cvv in the JSON to protect sensitive data
    };
  }
}
