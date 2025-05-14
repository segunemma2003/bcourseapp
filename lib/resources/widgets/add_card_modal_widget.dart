import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nylo_framework/nylo_framework.dart';

import '../../app/models/payment_card.dart';
import '../../app/networking/purchase_api_service.dart';

class AddCardModal extends NyStatefulWidget {
  final VoidCallback onCardAdded;

  AddCardModal({super.key, required this.onCardAdded});

  @override
  createState() => _AddCardModalState();
}

class _AddCardModalState extends NyState<AddCardModal> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Use a PaymentCard model to store form data
  late PaymentCard _paymentCard;

  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryMonthController = TextEditingController();
  final TextEditingController _expiryYearController = TextEditingController();
  final TextEditingController _cardHolderNameController =
      TextEditingController();
  final TextEditingController _cvvController = TextEditingController();

  String _detectedCardType = '';
  bool _isLoading = false;

  @override
  get init => () async {
        super.init();

        // Initialize the payment card model
        _paymentCard = PaymentCard(
          cardType: '',
          lastFour: '',
          cardHolderName: '',
          expiryMonth: '',
          expiryYear: '',
          isDefault: false,
        );
      };

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryMonthController.dispose();
    _expiryYearController.dispose();
    _cardHolderNameController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  // Detect card type from card number
  void _detectCardType(String cardNumber) {
    // Remove any spaces or dashes
    String cleanNumber = cardNumber.replaceAll(RegExp(r'[\s-]'), '');

    setState(() {
      if (cleanNumber.isEmpty) {
        _detectedCardType = '';
      } else if (cleanNumber.startsWith('4')) {
        _detectedCardType = 'Visa';
      } else if (RegExp(r'^5[1-5]').hasMatch(cleanNumber) ||
          RegExp(r'^2[2-7]').hasMatch(cleanNumber)) {
        _detectedCardType = 'MASTERCARD';
      } else if (RegExp(r'^3[47]').hasMatch(cleanNumber)) {
        _detectedCardType = 'American Express';
      } else if (RegExp(r'^6(?:011|5[0-9]{2})').hasMatch(cleanNumber)) {
        _detectedCardType = 'Discover';
      } else if (RegExp(r'^506(0|1|2|3|4|5)').hasMatch(cleanNumber) ||
          RegExp(r'^650[0-9]').hasMatch(cleanNumber)) {
        _detectedCardType = 'Verve';
      } else {
        _detectedCardType = 'unknown';
      }

      // Update the payment card model
      _paymentCard = PaymentCard(
        cardType: _detectedCardType,
        lastFour: _paymentCard.lastFour,
        cardHolderName: _paymentCard.cardHolderName,
        expiryMonth: _paymentCard.expiryMonth,
        expiryYear: _paymentCard.expiryYear,
        isDefault: _paymentCard.isDefault,
        cardNumber: cleanNumber,
        cvv: _paymentCard.cvv,
      );
    });
  }

  // Format card number with spaces
  String _formatCardNumber(String input) {
    // Remove any existing spaces
    String clean = input.replaceAll(' ', '');

    // For Amex (4-6-5 pattern)
    if (_detectedCardType == 'amex') {
      List<String> formatted = [];
      for (int i = 0; i < clean.length; i++) {
        if (i == 4 || i == 10) {
          formatted.add(' ');
        }
        formatted.add(clean[i]);
      }
      return formatted.join();
    }
    // For other cards (4-4-4-4 pattern)
    else {
      List<String> formatted = [];
      for (int i = 0; i < clean.length; i++) {
        if (i > 0 && i % 4 == 0) {
          formatted.add(' ');
        }
        formatted.add(clean[i]);
      }
      return formatted.join();
    }
  }

  Future<void> _saveCard() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Get the clean card number without spaces
        String cleanCardNumber = _cardNumberController.text.replaceAll(' ', '');
        // Extract the last 4 digits
        String lastFour = cleanCardNumber.substring(cleanCardNumber.length - 4);

        // Update the payment card model with form values
        _paymentCard = PaymentCard(
          cardType: _detectedCardType.isEmpty ? 'unknown' : _detectedCardType,
          lastFour: lastFour,
          cardHolderName: _cardHolderNameController.text,
          expiryMonth: _expiryMonthController.text,
          expiryYear: _expiryYearController.text,
          isDefault: _paymentCard.isDefault,
          cardNumber: cleanCardNumber,
          cvv: _cvvController.text,
        );

        // Use the API service to add the card
        var purchaseApiService = PurchaseApiService();
        await purchaseApiService.addPaymentCard(
          cardType: _paymentCard.cardType,
          lastFour: _paymentCard.lastFour,
          cardHolderName: _paymentCard.cardHolderName,
          expiryMonth: _paymentCard.expiryMonth,
          expiryYear: _paymentCard.expiryYear,
          isDefault: _paymentCard.isDefault,
        );

        // Call the callback to refresh payment methods
        widget.onCardAdded();

        // Show success message
        showToast(
          title: trans("Success"),
          description: trans("Card added successfully"),
          icon: Icons.check_circle,
          style: ToastNotificationStyleType.success,
        );

        // Close the modal
        Navigator.pop(context);
      } catch (e) {
        NyLogger.error('Failed to add card: $e');

        showToast(
          title: trans("Error"),
          description: trans("Failed to add card: ${e.toString()}"),
          icon: Icons.error_outline,
          style: ToastNotificationStyleType.danger,
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Build card type widget - using local asset for Visa, text for others
  Widget _buildCardTypeWidget(String cardType) {
    if (cardType == 'visa') {
      return Image.asset(
        "logos_visa.png",
        width: 40,
        height: 24,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            "VISA",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          );
        },
      ).localAsset();
    } else if (cardType == '') {
      // If no card type detected yet, show text for common card types
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("VISA",
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
          Text("MASTERCARD",
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
          Text("AMEX",
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      );
    } else {
      // For other card types, just display text
      String displayText = cardType.toUpperCase();
      if (cardType == 'mastercard') displayText = "MASTERCARD";
      if (cardType == 'amex') displayText = "AMEX";
      if (cardType == 'discover') displayText = "DISCOVER";
      if (cardType == 'verve') displayText = "VERVE";
      if (cardType == 'unknown') displayText = "CARD";

      return Text(
        displayText,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
    }
  }

  @override
  Widget view(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      trans("Add New Card"),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Card Number field with card type detection
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cardNumberController,
                        decoration: InputDecoration(
                          labelText: trans("Card Number"),
                          hintText: "XXXX XXXX XXXX XXXX",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(19),
                        ],
                        onChanged: (value) {
                          _detectCardType(value);

                          // Format the card number with spaces
                          final formatted = _formatCardNumber(value);
                          if (formatted != value) {
                            _cardNumberController.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                  offset: formatted.length),
                            );
                          }
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return trans("Please enter card number");
                          }

                          String cleanNumber = value.replaceAll(' ', '');
                          if (cleanNumber.length < 13 ||
                              cleanNumber.length > 19) {
                            return trans("Invalid card number length");
                          }

                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Container(
                      width: 70,
                      height: 40,
                      alignment: Alignment.center,
                      child: _buildCardTypeWidget(_detectedCardType),
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Card Holder Name
                TextFormField(
                  controller: _cardHolderNameController,
                  decoration: InputDecoration(
                    labelText: trans("Card Holder Name"),
                    hintText: "JOHN DOE",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) {
                    setState(() {
                      _paymentCard = PaymentCard(
                        cardType: _paymentCard.cardType,
                        lastFour: _paymentCard.lastFour,
                        cardHolderName: value,
                        expiryMonth: _paymentCard.expiryMonth,
                        expiryYear: _paymentCard.expiryYear,
                        isDefault: _paymentCard.isDefault,
                        cardNumber: _paymentCard.cardNumber,
                        cvv: _paymentCard.cvv,
                      );
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return trans("Please enter card holder name");
                    }
                    return null;
                  },
                ),

                SizedBox(height: 16),

                // Expiry Date and CVV in a row
                Row(
                  children: [
                    // Expiry Month
                    Expanded(
                      child: TextFormField(
                        controller: _expiryMonthController,
                        decoration: InputDecoration(
                          labelText: trans("Month"),
                          hintText: "MM",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _paymentCard = PaymentCard(
                              cardType: _paymentCard.cardType,
                              lastFour: _paymentCard.lastFour,
                              cardHolderName: _paymentCard.cardHolderName,
                              expiryMonth: value,
                              expiryYear: _paymentCard.expiryYear,
                              isDefault: _paymentCard.isDefault,
                              cardNumber: _paymentCard.cardNumber,
                              cvv: _paymentCard.cvv,
                            );
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return trans("Required");
                          }

                          int? month = int.tryParse(value);
                          if (month == null || month < 1 || month > 12) {
                            return trans("Invalid");
                          }

                          return null;
                        },
                      ),
                    ),

                    SizedBox(width: 12),

                    // Expiry Year
                    Expanded(
                      child: TextFormField(
                        controller: _expiryYearController,
                        decoration: InputDecoration(
                          labelText: trans("Year"),
                          hintText: "YY",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _paymentCard = PaymentCard(
                              cardType: _paymentCard.cardType,
                              lastFour: _paymentCard.lastFour,
                              cardHolderName: _paymentCard.cardHolderName,
                              expiryMonth: _paymentCard.expiryMonth,
                              expiryYear: value,
                              isDefault: _paymentCard.isDefault,
                              cardNumber: _paymentCard.cardNumber,
                              cvv: _paymentCard.cvv,
                            );
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return trans("Required");
                          }

                          int? year = int.tryParse(value);
                          int currentYear =
                              DateTime.now().year % 100; // Get last 2 digits

                          if (year == null || year < currentYear) {
                            return trans("Invalid");
                          }

                          return null;
                        },
                      ),
                    ),

                    SizedBox(width: 12),

                    // CVV
                    Expanded(
                      child: TextFormField(
                        controller: _cvvController,
                        decoration: InputDecoration(
                          labelText: trans("CVV"),
                          hintText: "XXX",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                              _detectedCardType == 'amex' ? 4 : 3),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _paymentCard = PaymentCard(
                              cardType: _paymentCard.cardType,
                              lastFour: _paymentCard.lastFour,
                              cardHolderName: _paymentCard.cardHolderName,
                              expiryMonth: _paymentCard.expiryMonth,
                              expiryYear: _paymentCard.expiryYear,
                              isDefault: _paymentCard.isDefault,
                              cardNumber: _paymentCard.cardNumber,
                              cvv: value,
                            );
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return trans("Required");
                          }

                          int expectedLength =
                              _detectedCardType == 'amex' ? 4 : 3;
                          if (value.length != expectedLength) {
                            return trans("Invalid");
                          }

                          return null;
                        },
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Default card checkbox
                CheckboxListTile(
                  title: Text(trans("Set as default payment method")),
                  value: _paymentCard.isDefault,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) {
                    setState(() {
                      _paymentCard = PaymentCard(
                        cardType: toTitleCase(_paymentCard.cardType),
                        lastFour: _paymentCard.lastFour,
                        cardHolderName: _paymentCard.cardHolderName,
                        expiryMonth: _paymentCard.expiryMonth,
                        expiryYear: _paymentCard.expiryYear,
                        isDefault: value ?? false,
                        cardNumber: _paymentCard.cardNumber,
                        cvv: _paymentCard.cvv,
                      );
                    });
                  },
                ),

                SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            trans("Add Card"),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String toTitleCase(String text) {
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
