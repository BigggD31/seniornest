import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:math';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/app_routes.dart';
import '../../core/app_state.dart';
import '../../services/auth_service.dart';

const String _monthlyProductId = 'com.devonmurphy.seniornest.monthly';
const String _yearlyProductId = 'com.devonmurphy.seniornest.yearly';
const String _additionalNestMonthlyProductId = 'com.devonmurphy.seniornest.additionalnest.monthly';
const String _additionalNestYearlyProductId = 'com.devonmurphy.seniornest.additionalnest.yearly';

class SubscribeNestScreen extends StatefulWidget {
  const SubscribeNestScreen({super.key});

  @override
  State<SubscribeNestScreen> createState() => _SubscribeNestScreenState();
}

class _SubscribeNestScreenState extends State<SubscribeNestScreen>
    with SingleTickerProviderStateMixin {
  bool _isYearly = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final InAppPurchase _iap = InAppPurchase.instance;
  bool _iapAvailable = false;
  bool _isPurchasing = false;
  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  // Sep 3 2026: the in_app_purchase plugin's purchaseStream can redeliver
  // the same purchase event more than once in quick succession (confirmed
  // live -- a real purchase fired twice, 578ms apart, creating two nests
  // from one purchase). Track purchase IDs already handled so a redelivery
  // is completed with the store but skipped for everything else below.
  final Set<String> _processedPurchaseIds = {};

  final TextEditingController _vipCodeController = TextEditingController();
  bool _showVipField = false;
  bool _isRedeemingVip = false;
  String? _vipError;

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
    _purchaseSubscription = _iap.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          _iap.completePurchase(purchase);
          // Always complete the purchase with the store above (required
          // regardless of dedup, or StoreKit keeps redelivering it), but
          // skip everything else if this exact purchase was already
          // fully processed once.
          final purchaseId = purchase.purchaseID;
          if (purchaseId != null) {
            if (_processedPurchaseIds.contains(purchaseId)) continue;
            _processedPurchaseIds.add(purchaseId);
          }
          await _recordSubscription(purchase.productID, purchase.purchaseID);
          if (_isAdditionalNest) await _createAdditionalNest();
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

  // True when this screen was opened from the "Create a new Nest" option in
  // the Home nest switcher -- an existing signed-in owner adding a second
  // nest, as opposed to a first-time signup. Read lazily via ModalRoute
  // (same pattern _navigateForward already uses) rather than cached in
  // initState, since route arguments aren't reliably available that early.
  bool get _isAdditionalNest {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return args?['additionalNest'] == true;
  }

  // Runs after a successful purchase/redemption when _isAdditionalNest is
  // true -- an existing signed-in owner adding a second nest, not a
  // first-time signup. The nest doesn't exist until this method creates it
  // (same reason nest_id was null on the subscription row this purchase
  // just recorded), so this mirrors the create-nest-then-attach pattern in
  // save_messages_prompt_screen.dart, then switches the app's active nest
  // to the new one so Home reflects it immediately on the next screen.
  Future<void> _createAdditionalNest() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || !mounted) return;

    final nameController = TextEditingController();
    final enteredName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Name Your New Nest',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 18)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. "Mom and Dad\'s House"'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final nestName = (enteredName != null && enteredName.isNotEmpty) ? enteredName : 'New Nest';

    String? nestId;
    for (int attempt = 0; attempt < 5 && nestId == null; attempt++) {
      final inviteCode = 'NEST${(100000 + Random().nextInt(900000))}';
      try {
        final nestResponse = await supabase
            .from('nests')
            .insert({'name': nestName, 'created_by': userId, 'invite_code': inviteCode})
            .select('id')
            .single();
        nestId = nestResponse['id'] as String;
      } on PostgrestException catch (e) {
        if (e.code == '23505') continue; // invite_code collision, retry
        rethrow;
      }
    }
    if (nestId == null) {
      debugPrint('ADDITIONAL_NEST_ERROR: could not generate a unique invite code after 5 attempts');
      return;
    }

    await supabase.from('nest_members').upsert(
      {'nest_id': nestId, 'user_id': userId},
      onConflict: 'nest_id,user_id',
    );

    // Attach this purchase's subscription row (still nest_id = NULL) to the
    // nest that just got created. Only touches a NULL row, so it can't
    // clobber this person's other nest(s).
    await supabase.from('subscriptions')
        .update({'nest_id': nestId})
        .eq('user_id', userId)
        .isFilter('nest_id', null);

    final prefs = await SharedPreferences.getInstance();
    await AuthService.clearStaleNestDataIfNestChanged(nestId);
    await prefs.setString('nest_id', nestId);
    await prefs.setString('nest_name', nestName);
    appNestNameNotifier.value = nestName;
  }

  // Sep 28 2026: covers a VIP redemption on this screen for an account that
  // turns out to have no nest at all yet -- see the call site's comment in
  // _redeemVipCode for the full explanation of the stuck-Home-skeleton bug
  // this fixes. Checks for an existing nest/membership first (unlike
  // _createAdditionalNest, which is only called when one is already known
  // not to exist) so this is safe to call unconditionally on every
  // non-additional-nest VIP redemption without disturbing an account that
  // already has a real nest.
  Future<void> _ensureNestExistsForVipRedemption() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();

    try {
      // Already owns a nest?
      final owned = await supabase
          .from('nests')
          .select('id, name')
          .eq('created_by', userId)
          .maybeSingle();
      if (owned != null) {
        final nestId = owned['id'] as String;
        final nestName = owned['name'] as String? ?? '';
        await prefs.setString('nest_id', nestId);
        if (nestName.isNotEmpty) {
          await prefs.setString('nest_name', nestName);
          appNestNameNotifier.value = nestName;
        }
        return;
      }

      // Already a member of someone else's nest?
      final membership = await supabase
          .from('nest_members')
          .select('nest_id, nests(name)')
          .eq('user_id', userId)
          .maybeSingle();
      if (membership != null) {
        final nestId = membership['nest_id'] as String;
        final nestRow = membership['nests'] as Map<String, dynamic>?;
        final nestName = nestRow?['name'] as String? ?? '';
        await prefs.setString('nest_id', nestId);
        if (nestName.isNotEmpty) {
          await prefs.setString('nest_name', nestName);
          appNestNameNotifier.value = nestName;
        }
        return;
      }
    } catch (e) {
      debugPrint('VIP_NEST_LOOKUP_ERROR: $e');
      // Can't confirm either way -- don't risk creating a duplicate nest
      // for someone who may already have one. Home's own _ensureNestId
      // will retry this same lookup on arrival.
      return;
    }

    // No existing nest or membership -- this VIP redemption never went
    // through the normal onboarding steps that would have created one, so
    // create it now. No "name your nest" prompt here (unlike
    // _createAdditionalNest): this happens for an account that hasn't
    // named anything yet, so fall back to whatever display name is cached
    // locally, same default Home itself would show.
    final preferredName = prefs.getString('preferred_name') ?? '';
    final displayName = prefs.getString('display_name') ?? '';
    final ownerName = preferredName.isNotEmpty ? preferredName : displayName;
    final nestName = ownerName.isNotEmpty ? "$ownerName's Nest" : 'My Nest';

    String? nestId;
    for (int attempt = 0; attempt < 5 && nestId == null; attempt++) {
      final inviteCode = 'NEST${(100000 + Random().nextInt(900000))}';
      try {
        final nestResponse = await supabase
            .from('nests')
            .insert({'name': nestName, 'created_by': userId, 'invite_code': inviteCode})
            .select('id')
            .single();
        nestId = nestResponse['id'] as String;
      } on PostgrestException catch (e) {
        if (e.code == '23505') continue; // invite_code collision, retry
        rethrow;
      }
    }
    if (nestId == null) {
      debugPrint('VIP_NEST_CREATE_ERROR: could not generate a unique invite code after 5 attempts');
      return;
    }

    await supabase.from('nest_members').upsert(
      {'nest_id': nestId, 'user_id': userId},
      onConflict: 'nest_id,user_id',
    );

    // Attach this redemption's subscription row (still nest_id = NULL,
    // written by the redeem_vip_code RPC just above) to the nest that just
    // got created -- same pattern _createAdditionalNest uses for a
    // purchase. Only touches a NULL row, so it can't clobber another nest.
    await supabase.from('subscriptions')
        .update({'nest_id': nestId})
        .eq('user_id', userId)
        .isFilter('nest_id', null);

    await AuthService.clearStaleNestDataIfNestChanged(nestId);
    await prefs.setString('nest_id', nestId);
    await prefs.setString('nest_name', nestName);
    appNestNameNotifier.value = nestName;
  }

  // Actually records the purchase in Supabase so the rest of the app can
  // tell whether this person is currently entitled. Previously nothing
  // wrote this down anywhere -- purchasing and access were disconnected.
  // nestId is null for a first-time signup subscribing before their nest
  // exists (confirmed via splash_screen.dart trace -- Get Started sends
  // people here before roleChoiceScreen/nest creation). It gets attached
  // retroactively once the nest is actually created. For someone creating
  // an *additional* nest from an existing account, the nest already exists
  // by the time they land here, so nestId will be passed in directly.
  Future<void> _recordSubscription(String productId, String? transactionId, {String? nestId}) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      final now = DateTime.now();
      // Soft expiry estimate used between launches; re-verified against
      // Apple via restorePurchases() each time the app opens (see main.dart).
      // Lifetime/promo entitlements never expire.
      DateTime? expiresAt;
      String status = 'active';
      if (productId == _yearlyProductId || productId == _additionalNestYearlyProductId) {
        expiresAt = now.add(const Duration(days: 365));
      } else if (productId == _monthlyProductId || productId == _additionalNestMonthlyProductId) {
        expiresAt = now.add(const Duration(days: 30));
      } else {
        // promo / lifetime-style entitlement
        expiresAt = null;
        status = 'lifetime';
      }
      final row = {
        'user_id': userId,
        'nest_id': nestId,
        'product_id': productId,
        'status': status,
        'purchase_date': now.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'transaction_id': transactionId,
        'updated_at': now.toIso8601String(),
      };
      // Explicit check-then-write instead of upsert(onConflict: 'user_id,nest_id'):
      // Postgres unique constraints don't treat NULL = NULL, so a plain
      // upsert wouldn't reliably catch a retry/double-tap when nestId is null
      // (the first-time-signup case). Mirrors the same pattern used in the
      // redeem_vip_code() DB function for the same reason.
      var query = supabase.from('subscriptions').select('id').eq('user_id', userId);
      query = nestId == null ? query.isFilter('nest_id', null) : query.eq('nest_id', nestId);
      final existing = await query.maybeSingle();
      if (existing != null) {
        await supabase.from('subscriptions').update(row).eq('id', existing['id'] as String);
      } else {
        await supabase.from('subscriptions').insert(row);
      }
    } catch (e) {
      debugPrint('SUBSCRIPTION_RECORD_ERROR: $e');
    }
  }

  Future<void> _initIAP() async {
    final available = await _iap.isAvailable();
    if (!mounted) return;
    setState(() => _iapAvailable = available);
    if (available) {
      // Read _isAdditionalNest here, after the async gap above, not before
      // it -- ModalRoute arguments aren't reliably available synchronously
      // in initState (see _isAdditionalNest's own comment; _initIAP is
      // called directly from initState at construction).
      final productIds = _isAdditionalNest
          ? {_additionalNestMonthlyProductId, _additionalNestYearlyProductId}
          : {_monthlyProductId, _yearlyProductId};
      final response = await _iap.queryProductDetails(productIds);
      if (!mounted) return;
      setState(() => _products = response.productDetails);
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _animController.dispose();
    _vipCodeController.dispose();
    super.dispose();
  }

  // p_nest_id is left null in the RPC call below for the same reason
  // _recordSubscription() leaves nestId null on this screen -- at this
  // point the nest doesn't exist yet, whether this is a first-time signup
  // or an existing owner adding a second nest. save_messages_prompt_screen.dart
  // (first-time) and _createAdditionalNest() below (existing owner) each
  // attach the real nest_id retroactively once their nest actually gets created.
  Future<void> _redeemVipCode() async {
    final code = _vipCodeController.text.trim();
    if (code.isEmpty || _isRedeemingVip) return;
    setState(() { _isRedeemingVip = true; _vipError = null; });
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() { _isRedeemingVip = false; _vipError = 'Please sign in first.'; });
        return;
      }
      final result = await supabase.rpc('redeem_vip_code', params: {
        'p_code': code,
        'p_user_id': userId,
        'p_nest_id': null,
      });
      if (!mounted) return;
      if (result == true) {
        if (_isAdditionalNest) {
          await _createAdditionalNest();
        } else {
          // Sep 28 2026: D Von's direct report -- redeeming a VIP code here
          // landed on a stuck loading skeleton on Home. Root cause: this
          // branch used to do nothing but navigate straight to Home for
          // every non-additional-nest redemption, on the unstated
          // assumption that an already-signed-in account always already
          // has a nest by the time it can reach this screen. That's true
          // for the common paths (an existing owner/member whose
          // entitlement lapsed), but not guaranteed -- an account that's
          // signed in and locally flagged as onboarded on THIS device can
          // still have no real nest/membership row at all (e.g. a fresh
          // sign-in on a new device/reinstall before this device's own
          // onboarding ever ran, or any other gap between "signed in" and
          // "actually has a nest"). Home's _isLoading starts true whenever
          // appNestNameNotifier is empty and only ever resolves once a
          // real nest is found -- with no nest to find, it never does.
          // This mirrors _createAdditionalNest()'s own create-then-attach
          // pattern, but checks for an existing nest first (unlike that
          // method, which is only ever called when one is already known
          // not to exist) and skips the "name your nest" prompt, since a
          // VIP redemption on this screen never went through the normal
          // onboarding steps that would have collected a name.
          await _ensureNestExistsForVipRedemption();
        }
        if (!mounted) return;
        _navigateForward();
      } else {
        setState(() {
          _isRedeemingVip = false;
          _vipError = "That code isn't valid or has already been fully used.";
        });
      }
    } catch (e) {
      debugPrint('VIP_CODE_REDEEM_ERROR: $e');
      if (!mounted) return;
      setState(() { _isRedeemingVip = false; _vipError = 'Something went wrong. Please try again.'; });
    }
  }

  void _onSubscribeNow() async {
    if (_isPurchasing) return;

    final productId = _isAdditionalNest
        ? (_isYearly ? _additionalNestYearlyProductId : _additionalNestMonthlyProductId)
        : (_isYearly ? _yearlyProductId : _monthlyProductId);
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  static const String _heroAsset = 'assets/images/pricing_hero_tablet.jpg';
  static const Color _teal = Color(0xFF5DA399);
  static const Color _gold = Color(0xFFC8922A);
  static const Color _ink = Color(0xFF2C2417);

  // Sep 26 2026: rebuilt as a full-bleed photo hero, matching the approved
  // Pricing-Fullbleed Claude Design mockup D Von signed off on -- same
  // real Monthly/Yearly toggle, same $9.99/mo vs $99/yr copy, same IAP,
  // VIP-redemption and additional-nest logic as before, just reskinned
  // onto the photo instead of the plain card layout it replaces.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _heroAsset,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.5),
          ),

          // Top scrim -- just enough for the back button to read. Sep 27
          // 2026: lightened (was 0x8C) so more of the photo shows through,
          // per D Von's direct ask.
          Container(
            height: 140,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x63140F08), Color(0x00140F08)],
              ),
            ),
          ),

          // Bottom scrim -- carries all the copy. Sep 27 2026: lightened
          // (was 0xB8/0xF5) so more of the photo shows through, per D
          // Von's direct ask.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.34, 1.0],
                colors: [
                  Color(0x00140F08),
                  Color(0x8C140F08),
                  Color(0xD8140F08),
                ],
              ),
            ),
          ),

          SafeArea(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) => SlideTransition(
                position: _slideAnim,
                child: Opacity(opacity: _fadeAnim.value, child: child),
              ),
              child: Column(
                children: [
                  _buildHeader(),
                  // Sep 28 2026: the Sep 26 full-bleed rebuild dropped the
                  // Expanded wrapper this scroll view used to have (see git
                  // history at commit 043c569), replacing it with a bare
                  // Spacer + unconstrained SingleChildScrollView. Without
                  // Expanded, the scroll view sizes itself to its own
                  // content instead of the real remaining screen height, so
                  // when tapping "Have a VIP code?" grows _buildContent()
                  // (swapping the text link for a field + button), the
                  // added height has nowhere to scroll into and gets
                  // clipped off-screen -- D Von's direct report: the button
                  // "disappears and nothing happens." Expanded restores a
                  // real bounded height so it scrolls properly again;
                  // Align(bottomCenter) keeps the content anchored to the
                  // bottom of that space when it's shorter than the screen,
                  // matching the original bottom-sheet-over-photo look.
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: _buildContent(),
                      ),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 19)),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(100)),
          child: Text('Takes about a minute',
            style: GoogleFonts.manrope(fontSize: 10.5,
              fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9))),
        ),
      ]),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('YOUR FIRST 3 DAYS',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunitoSans(fontSize: 11.5,
            fontWeight: FontWeight.w800, letterSpacing: 1.2, color: _gold)),
        const SizedBox(height: 8),
        Text("Welcome to your family's private nest.",
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(fontSize: 25,
            fontWeight: FontWeight.w800, color: Colors.white, height: 1.18,
            shadows: const [Shadow(blurRadius: 10, color: Color(0x4D000000))])),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: _gold.withValues(alpha: 0.55), width: 1.5)),
          child: Text('One person pays — everyone else joins free',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 12,
              fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(height: 18),
        _buildPricingToggle(),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isPurchasing ? null : _onSubscribeNow,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white, elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100))),
            child: _isPurchasing
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Start My 3-Day Free Trial', style: GoogleFonts.manrope(
                      fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                ]),
          ),
        ),
        const SizedBox(height: 10),
        Text('No payment required right now · Cancel anytime',
          style: GoogleFonts.manrope(fontSize: 11,
            fontWeight: FontWeight.w400, color: Colors.white.withValues(alpha: 0.65)),
          textAlign: TextAlign.center),
        const SizedBox(height: 14),
        _buildLegalLinks(),
        const SizedBox(height: 12),
        _buildVipCodeSection(),
      ],
    );
  }

  Widget _buildVipCodeSection() {
    if (!_showVipField) {
      return Center(
        child: GestureDetector(
          onTap: () => setState(() => _showVipField = true),
          child: Text('Have a VIP code?',
            style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700,
              color: _gold, decoration: TextDecoration.underline,
              decorationColor: _gold)),
        ),
      );
    }
    return Column(children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _vipCodeController,
            textCapitalization: TextCapitalization.characters,
            enabled: !_isRedeemingVip,
            onSubmitted: (_) => _redeemVipCode(),
            style: GoogleFonts.manrope(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter VIP code',
              hintStyle: GoogleFonts.manrope(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: _isRedeemingVip ? null : _redeemVipCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _ink, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: _isRedeemingVip
              ? SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _ink))
              : Text('Apply', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
      if (_vipError != null) ...[
        const SizedBox(height: 8),
        Text(_vipError!, style: GoogleFonts.manrope(fontSize: 12,
          fontWeight: FontWeight.w500, color: const Color(0xFFFFAA8A))),
      ],
    ]);
  }

  Widget _buildLegalLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => _launchUrl('https://seniornestapp.com/privacy.html'),
          child: Text('Privacy Policy',
            style: GoogleFonts.manrope(fontSize: 11,
              color: Colors.white.withValues(alpha: 0.7),
              decoration: TextDecoration.underline))),
        Text('  ·  ',
          style: GoogleFonts.manrope(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
        GestureDetector(
          onTap: () => _launchUrl('https://seniornestapp.com/terms.html'),
          child: Text('Terms of Use',
            style: GoogleFonts.manrope(fontSize: 11,
              color: Colors.white.withValues(alpha: 0.7),
              decoration: TextDecoration.underline))),
      ],
    );
  }

  Widget _buildPricingToggle() {
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(100)),
        child: Row(children: [
          _buildToggleOption(label: 'Monthly', isSelected: !_isYearly,
            onTap: () => setState(() => _isYearly = false)),
          _buildToggleOption(label: 'Yearly', isSelected: _isYearly,
            onTap: () => setState(() => _isYearly = true), badge: 'Save 15%'),
        ]),
      ),
      const SizedBox(height: 12),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isYearly
          ? _buildPriceLine(key: const ValueKey('yearly'),
              price: r'$99', period: '/ year',
              subtitle: 'Billed annually — just \$8.25/month')
          : _buildPriceLine(key: const ValueKey('monthly'),
              price: r'$9.99', period: '/ month',
              subtitle: 'Billed monthly, cancel anytime'),
      ),
    ]);
  }

  Widget _buildToggleOption({required String label, required bool isSelected,
    required VoidCallback onTap, String? badge}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(100)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: GoogleFonts.manrope(fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isSelected ? _ink : Colors.white.withValues(alpha: 0.75))),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(badge, style: GoogleFonts.manrope(fontSize: 9,
                  fontWeight: FontWeight.w800, color: const Color(0xFFF0C878)))),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildPriceLine({required Key key, required String price,
    required String period, required String subtitle}) {
    return Column(
      key: key,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
          Text(price, style: GoogleFonts.manrope(fontSize: 27,
            fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(width: 5),
          Text(period, style: GoogleFonts.manrope(fontSize: 13,
            fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.65))),
        ]),
        const SizedBox(height: 2),
        Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 12,
          fontWeight: FontWeight.w400, color: Colors.white.withValues(alpha: 0.7))),
      ],
    );
  }
}
