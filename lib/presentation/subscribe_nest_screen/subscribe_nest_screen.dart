import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../routes/app_routes.dart';

const String _monthlyProductId = 'com.devonmurphy.seniornest.monthly';
const String _yearlyProductId = 'com.devonmurphy.seniornest.yearly';

class SubscribeNestScreen extends StatefulWidget {
  const SubscribeNestScreen({super.key});

  @override
  State<SubscribeNestScreen> createState() => _SubscribeNestScreenState();
}

class _SubscribeNestScreenState extends State<SubscribeNestScreen>
    with SingleTickerProviderStateMixin {
  bool _isYearly = false;
  bool _promoApplied = false;
  String _promoError = '';
  final TextEditingController _promoController = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final InAppPurchase _iap = InAppPurchase.instance;
  bool _iapAvailable = false;
  bool _isPurchasing = false;
  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
    _initIAP();
    _purchaseSubscription = _iap.purchaseStream.listen((purchases) {
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          _iap.completePurchase(purchase);
          if (mounted) {
            setState(() => _isPurchasing = false);
            _navigateForward();
          }
        } else if (purchase.status == PurchaseStatus.error) {
          if (mounted) setState(() => _isPurchasing = false);
        } else if (purchase.status == PurchaseStatus.pending) {
          if (mounted) setState(() => _isPurchasing = true);
        }
      }
    });
  }

  Future<void> _initIAP() async {
    final available = await _iap.isAvailable();
    if (!mounted) return;
    setState(() => _iapAvailable = available);
    if (available) {
      final response = await _iap.queryProductDetails(
        {_monthlyProductId, _yearlyProductId});
      if (!mounted) return;
      setState(() => _products = response.productDetails);
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _animController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  void _onSubscribeNow() async {
    if (_isPurchasing) return;

    final productId = _isYearly ? _yearlyProductId : _monthlyProductId;
    final product = _products.where((p) => p.id == productId).firstOrNull;

    if (product != null && _iapAvailable) {
      setState(() => _isPurchasing = true);
      final purchaseParam = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      setState(() => _isPurchasing = false);
    } else {
      _navigateForward();
    }
  }

  void _navigateForward() {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {};
    final returnRoute = args['returnRoute'] as String? ?? AppRoutes.familyFeedScreen;
    final returnArgs = args['returnArgs'] as Map<String, dynamic>? ?? {};
    Navigator.pushReplacementNamed(context, returnRoute,
        arguments: {...returnArgs, 'startAtStep': 1});
  }

  void _applyPromoCode() {
    final code = _promoController.text.trim().toUpperCase();
    if (code == 'LIFETIME2026') {
      setState(() { _promoApplied = true; _promoError = ''; });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _navigateForward();
      });
    } else {
      setState(() => _promoError = 'Invalid promo code. Please try again.');
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDFDFD), Color(0xFFF5F0E8)],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, child) => SlideTransition(
              position: _slideAnim,
              child: Opacity(opacity: _fadeAnim.value, child: child),
            ),
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('One-time setup only—takes just a minute!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunitoSans(fontSize: 12,
                      fontWeight: FontWeight.w400, color: const Color(0xFFB0A898))),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 60 : 28, vertical: 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isTablet ? 500 : 420),
                      child: _buildContent(isTablet),
                    ),
                  ),
                ),
                _buildSubscribeButton(isTablet),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF5DA399).withAlpha(31),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.arrow_back_rounded,
              color: Color(0xFF5DA399), size: 22)),
        ),
        const Spacer(),
      ]),
    );
  }

  Widget _buildContent(bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Subscribe to Your Nest',
          style: GoogleFonts.manrope(fontSize: isTablet ? 30 : 26,
            fontWeight: FontWeight.w800, color: const Color(0xFF2C2417), height: 1.2)),
        const SizedBox(height: 8),
        Text('Keep your family connected with everything SeniorNest has to offer.',
          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w400,
            color: const Color(0xFF7A6E5F), height: 1.5)),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF5DA399).withAlpha(26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF5DA399).withAlpha(60), width: 1)),
          child: Row(children: [
            const Icon(Icons.people_alt_rounded, color: Color(0xFF5DA399), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('One person pays — the whole family connects for free.',
              style: GoogleFonts.manrope(fontSize: 13,
                fontWeight: FontWeight.w600, color: const Color(0xFF3D7A72)))),
          ]),
        ),
        const SizedBox(height: 28),
        _buildPricingToggle(),
        const SizedBox(height: 28),
        _buildBenefitsList(),
        const SizedBox(height: 20),
        _buildLegalLinks(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildLegalLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => _launchUrl('https://seniornestapp.com/privacy.html'),
          child: Text('Privacy Policy',
            style: GoogleFonts.manrope(fontSize: 12,
              color: const Color(0xFF5DA399),
              decoration: TextDecoration.underline))),
        Text('  •  ',
          style: GoogleFonts.manrope(fontSize: 12, color: const Color(0xFF9E9080))),
        GestureDetector(
          onTap: () => _launchUrl('https://seniornestapp.com/terms.html'),
          child: Text('Terms of Use',
            style: GoogleFonts.manrope(fontSize: 12,
              color: const Color(0xFF5DA399),
              decoration: TextDecoration.underline))),
      ],
    );
  }

  Widget _buildPricingToggle() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EBE0),
          borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          _buildToggleOption(label: 'Monthly', isSelected: !_isYearly,
            onTap: () => setState(() => _isYearly = false)),
          _buildToggleOption(label: 'Yearly', isSelected: _isYearly,
            onTap: () => setState(() => _isYearly = true), badge: 'Save 15%'),
        ]),
      ),
      const SizedBox(height: 20),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isYearly
          ? _buildPriceCard(key: const ValueKey('yearly'),
              price: r'$99', period: '/ year',
              subtitle: 'Billed annually — just \$8.25/month',
              accentColor: const Color(0xFFD4A853))
          : _buildPriceCard(key: const ValueKey('monthly'),
              price: r'$9.99', period: '/ month',
              subtitle: 'Billed monthly, cancel anytime',
              accentColor: const Color(0xFF5DA399)),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildToggleOption({required String label, required bool isSelected,
    required VoidCallback onTap, String? badge}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withAlpha(18),
              blurRadius: 8, offset: const Offset(0, 2))] : null),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: GoogleFonts.manrope(fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? const Color(0xFF2C2417) : const Color(0xFF9E9080))),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A853).withAlpha(40),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(badge, style: GoogleFonts.manrope(fontSize: 10,
                  fontWeight: FontWeight.w700, color: const Color(0xFFB8892A)))),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildPriceCard({required Key key, required String price,
    required String period, required String subtitle, required Color accentColor}) {
    return Container(
      key: key, width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withAlpha(80), width: 1.5),
        boxShadow: [BoxShadow(color: accentColor.withAlpha(30),
          blurRadius: 20, offset: const Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(price, style: GoogleFonts.manrope(fontSize: 42,
            fontWeight: FontWeight.w800, color: const Color(0xFF2C2417), height: 1.0)),
          const SizedBox(width: 4),
          Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Text(period, style: GoogleFonts.manrope(fontSize: 16,
              fontWeight: FontWeight.w500, color: const Color(0xFF9E9080)))),
        ]),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.manrope(fontSize: 13,
          fontWeight: FontWeight.w400, color: const Color(0xFF9E9080))),
      ]),
    );
  }

  Widget _buildBenefitsList() {
    final benefits = [
      (Icons.check_circle_rounded, 'Daily check-in & wellness tracking'),
      (Icons.check_circle_rounded, 'Family feed with photos & messages'),
      (Icons.check_circle_rounded, 'Medication & appointment reminders'),
      (Icons.check_circle_rounded, 'Legacy stories & memory vault'),
      (Icons.check_circle_rounded, 'Unlimited family members — free'),
      (Icons.check_circle_rounded, 'Safety alerts & emergency contacts'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("What's included", style: GoogleFonts.manrope(fontSize: 15,
        fontWeight: FontWeight.w700, color: const Color(0xFF2C2417))),
      const SizedBox(height: 14),
      ...benefits.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(b.$1, color: const Color(0xFF5DA399), size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(b.$2, style: GoogleFonts.manrope(fontSize: 14,
            fontWeight: FontWeight.w500, color: const Color(0xFF4A3F30), height: 1.4))),
        ]),
      )),
    ]);
  }

  Widget _buildSubscribeButton(bool isTablet) {
    return Container(
      padding: EdgeInsets.fromLTRB(isTablet ? 60 : 28, 16, isTablet ? 60 : 28,
        MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFD),
        border: Border(top: BorderSide(
          color: const Color(0xFF2C2417).withAlpha(15), width: 1))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _isPurchasing ? null : _onSubscribeNow,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5DA399),
              foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16))),
            child: _isPurchasing
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text('Start 3-Day Free Trial', style: GoogleFonts.manrope(
                  fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 8),
        Text('No payment required right now — set up first.',
          style: GoogleFonts.manrope(fontSize: 12,
            fontWeight: FontWeight.w400, color: const Color(0xFF9E9080)),
          textAlign: TextAlign.center),
      ]),
    );
  }
}
