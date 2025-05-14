import 'package:nylo_framework/nylo_framework.dart';

class User extends Model {
  final int id;
  final String email;
  final String fullName;
  final String phoneNumber;
  final String? dateOfBirth;

  static String storageKey = "user";

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    this.dateOfBirth,
  }) : super(key: storageKey);

  User.fromJson(dynamic data)
      : id = data['id'] ?? 0,
        email = data['email'] ?? '',
        fullName = data['full_name'] ?? '',
        phoneNumber = data['phone_number'] ?? '',
        dateOfBirth = data['date_of_birth'],
        super(key: storageKey);

  @override
  toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'date_of_birth': dateOfBirth,
    };
  }
}
