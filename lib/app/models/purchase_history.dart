import 'package:nylo_framework/nylo_framework.dart';

class PurchaseHistory extends Model {
  final int id;
  final int course;
  final String course_title;
  final String? course_image;
  final int? payment_card;
  final String? card_last_four; // Make nullable
  final String amount;
  final DateTime purchase_date;
  final String? transaction_id; // Make nullable
  final String payment_status;
  final String? razorpay_order_id;
  final String? razorpay_payment_id;

  static StorageKey key = "purchase_history";

  PurchaseHistory({
    required this.id,
    required this.course,
    required this.course_title,
    this.course_image,
    this.payment_card,
    this.card_last_four, // Now nullable
    required this.amount,
    required this.purchase_date,
    this.transaction_id, // Now nullable
    required this.payment_status,
    this.razorpay_order_id,
    this.razorpay_payment_id,
  }) : super(key: key);

  PurchaseHistory.fromJson(Map<String, dynamic> data)
      : id = data['id'],
        course = data['course'],
        course_title =
            data['course_title'] ?? 'Unknown Course', // Add fallback value
        course_image = data['course_image'],
        payment_card = data['payment_card'],
        card_last_four = data['card_last_four'] ?? 'XXXX', // Add fallback value
        amount = data['amount'] ?? '0.00', // Add fallback value
        purchase_date = data['purchase_date'] != null
            ? DateTime.parse(data['purchase_date'])
            : DateTime.now(), // Add fallback value
        transaction_id = data['transaction_id'],
        payment_status =
            data['payment_status'] ?? 'Unknown', // Add fallback value
        razorpay_order_id = data['razorpay_order_id'],
        razorpay_payment_id = data['razorpay_payment_id'],
        super(key: key);

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'course': course,
      'course_title': course_title,
      'course_image': course_image,
      'payment_card': payment_card,
      'card_last_four': card_last_four,
      'amount': amount,
      'purchase_date': purchase_date.toIso8601String(),
      'transaction_id': transaction_id,
      'payment_status': payment_status,
      'razorpay_order_id': razorpay_order_id,
      'razorpay_payment_id': razorpay_payment_id,
    };
  }
}
