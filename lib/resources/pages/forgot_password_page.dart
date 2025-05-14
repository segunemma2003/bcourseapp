import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

class ForgotPasswordPage extends NyStatefulWidget {

  static RouteView path = ("/forgot-password", (_) => ForgotPasswordPage());
  
  ForgotPasswordPage({super.key}) : super(child: () => _ForgotPasswordPageState());
}

class _ForgotPasswordPageState extends NyPage<ForgotPasswordPage> {

  @override
  get init => () {

  };

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Forgot Password")
      ),
      body: SafeArea(
         child: Container(),
      ),
    );
  }
}
