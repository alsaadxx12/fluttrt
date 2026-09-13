import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';

class CinemanaScreen extends StatefulWidget {
  final String initialUrl;
  final String title;

  const CinemanaScreen({
    super.key,
    required this.initialUrl,
    required this.title,
  });

  @override
  State<CinemanaScreen> createState() => _CinemanaScreenState();
}

class _CinemanaScreenState extends State<CinemanaScreen> {
  WebViewController? _controller;
  int _loadingProgress = 0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didUpdateWidget(covariant CinemanaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl != widget.initialUrl) {
      _controller?.loadRequest(Uri.parse(widget.initialUrl));
    }
  }

  void _initWebView() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _loadingProgress = progress;
                  _isLoading = progress < 100;
                });
              }
            },
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
              }
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
                // Automatically click 'الاستمرار في الموقع' if the Shabakaty app store prompt is displayed
                _controller?.runJavaScript('''
                  (function() {
                    function autoDismiss() {
                      var elements = document.querySelectorAll('button, a, div, span');
                      for (var i = 0; i < elements.length; i++) {
                        if (elements[i].textContent && elements[i].textContent.trim() === 'الاستمرار في الموقع') {
                          elements[i].click();
                          break;
                        }
                      }
                    }
                    setTimeout(autoDismiss, 400);
                    setTimeout(autoDismiss, 1200);
                  })();
                ''');
              }
            },
            onWebResourceError: (error) {
              if (mounted && error.isForMainFrame == true) {
                setState(() {
                  _errorMessage = error.description;
                  _isLoading = false;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.initialUrl));

      _controller = controller;
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.parse(widget.initialUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_controller != null && await _controller!.canGoBack()) {
          await _controller!.goBack();
        } else {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: isDark ? const Color(0xFF131317) : Colors.white,
        elevation: 1,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.movie_filter_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Text(
                    'شبكتي سينمانا • Shabakaty Cinemana',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_controller != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              tooltip: 'الصفحة السابقة',
              onPressed: () async {
                if (await _controller!.canGoBack()) {
                  await _controller!.goBack();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              tooltip: 'الصفحة التالية',
              onPressed: () async {
                if (await _controller!.canGoForward()) {
                  await _controller!.goForward();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'تحديث',
              onPressed: () => _controller!.reload(),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded, size: 20),
            tooltip: 'فتح في المتصفح الخارجي',
            onPressed: _openInExternalBrowser,
          ),
          const SizedBox(width: 4),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2.5),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress / 100.0 : null,
                  backgroundColor: Colors.transparent,
                  color: AppColors.primary,
                  minHeight: 2.5,
                ),
              )
            : null,
      ),
      body: _buildBody(context, isDark),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.devices_rounded, size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text(
                'تصفح شبكتي سينمانا',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'تصفح سينمانا المدمج مدعوم مباشرة داخل تطبيق الموبايل، يمكنك فتح الرابط الآن على سطح المكتب عبر المتصفح:',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.darkTextSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _openInExternalBrowser,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('فتح موقع سينمانا'),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 54, color: AppColors.error),
              const SizedBox(height: 16),
              const Text(
                'تعذر تحميل صفحة سينمانا',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'تأكد من الاتصال بشبكة الإنترنت أو شبكة إيرثلنك/شبكتي\n$_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.darkTextSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                        _isLoading = true;
                      });
                      _controller?.loadRequest(Uri.parse(widget.initialUrl));
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _openInExternalBrowser,
                    icon: const Icon(Icons.open_in_browser_rounded),
                    label: const Text('فتح بالمتصفح'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return WebViewWidget(controller: _controller!);
  }
}
