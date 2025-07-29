import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PrivacyPolicyPage extends NyStatefulWidget {
  static RouteView path = ("/privacy-policy", (_) => PrivacyPolicyPage());

  PrivacyPolicyPage({super.key})
      : super(child: () => _PrivacyPolicyPageState());
}

class _PrivacyPolicyPageState extends NyPage<PrivacyPolicyPage> {
  late WebViewController _webViewController;
  bool _isLoading = true;
  final String _privacyPolicyUrl =
      'https://bybhavani.com/Intellectual_Property_and_Data_Usage_Policy.php';

  @override
  get init => () async {
        _initializeWebView();
      };

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading progress if needed
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            NyLogger.error('WebView error: ${error.description}');
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(_privacyPolicyUrl));
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
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              "Privacy Policy",
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
            actions: [
              // Refresh button
              IconButton(
                icon: Icon(Icons.refresh, color: Colors.black),
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                  });
                  _webViewController.reload();
                },
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // WebView
          WebViewWidget(controller: _webViewController),

          // Loading indicator overlay
          if (_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading Privacy Policy...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
