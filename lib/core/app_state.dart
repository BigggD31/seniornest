import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';


/// Global notifier — setup_screen writes here; MyApp rebuilds immediately.
final ValueNotifier<double> appTextScaleNotifier = ValueNotifier<double>(1.0);

/// Global dark-mode notifier — setup_screen writes here; MyApp switches ThemeMode.
final ValueNotifier<bool> appDarkModeNotifier = ValueNotifier<bool>(false);

/// Global nest-name notifier — resolved once in main.dart's
/// _resolveInitialRoute(), before any screen ever builds, same pattern as
/// appDarkModeNotifier above. Once someone has named their nest, that name
/// should appear everywhere instantly with nothing ever shown below it --
/// no "My Nest"/"Your Nest" placeholder flash, regardless of connection
/// speed. An earlier fix seeded each screen's own local nest-name field
/// from cache before starting its network re-check, which helped, but
/// still had a small unavoidable async gap (reading SharedPreferences
/// itself). This closes that gap completely: any screen that needs the
/// nest name reads this notifier's already-resolved value directly and
/// synchronously, the same way dark mode already works. Screens that
/// fetch a live, possibly-renamed value from Supabase should update this
/// notifier too, so every other screen picks up the change immediately.
final ValueNotifier<String> appNestNameNotifier = ValueNotifier<String>('');

/// Global returning-user notifier -- resolved once in main.dart's
/// _resolveInitialRoute(), before any screen ever builds, same pattern as
/// the two notifiers above. True when this device just signed out (the
/// only scenario where splash_screen needs to show a lean "Welcome back"
/// sign-in view instead of the full first-time pitch). Reading the
/// underlying just_signed_out flag asynchronously inside splash_screen
/// itself would flash the full pitch briefly before switching layouts --
/// exactly the class of bug fixed everywhere else tonight -- so it's
/// resolved here instead and read synchronously at field declaration.
final ValueNotifier<bool> appIsReturningUserNotifier = ValueNotifier<bool>(false);

/// Global nest-ownership notifier -- resolved once in main.dart's
/// _resolveInitialRoute(), before any screen ever builds, same pattern as
/// the notifiers above. Two screens (setup_screen and family_feed_screen)
/// each independently declared their own "bool _isNestOwner = false;" and
/// corrected it asynchronously after mount -- the exact flash-of-wrong-
/// content pattern documented Aug 14 2026 (Popy's role badge showing
/// "Member" for a frame before flipping to "Nest Owner"). One shared,
/// synchronously-readable source of truth fixes the flash on both screens
/// at once instead of patching each screen's timing independently, and
/// keeps them from ever disagreeing with each other.
final ValueNotifier<bool> appIsNestOwnerNotifier = ValueNotifier<bool>(false);

/// Global today's-check-in-status notifier -- resolved once in main.dart's
/// _resolveInitialRoute() from the existing date-scoped
/// cached_checkin_checked_in/cached_checkin_date prefs (see
/// family_feed_screen's _loadData for the original per-screen version of
/// this same scoping logic). Fixes the "I'm Good" button flashing on
/// screen for a frame before hiding, documented Aug 14 2026 -- same root
/// cause as appIsNestOwnerNotifier above: family_feed_screen declared
/// "bool _seniorCheckedInToday = false;" and only corrected it after an
/// async cache read that couldn't finish before the first frame painted.
final ValueNotifier<bool> appSeniorCheckedInTodayNotifier = ValueNotifier<bool>(false);

/// Suppresses the ambient KeyboardDoneBar/KeyboardDoneBarOverlay while a
/// single-line field with its own native "Done" key has focus. The bar
/// exists specifically for multi-line fields, where Return can't also mean
/// "close the keyboard" -- but because the bar is ambient (MediaQuery's
/// keyboard inset isn't scoped per-field), it was showing up even on
/// single-line fields that already have their own native done button,
/// producing two checkmark-style controls on screen at once. D Von
/// reported this on Setup's Rename Nest sheet (Aug 15 2026 build 171
/// follow-up). Single-line fields call suppressKeyboardBarWhileFocused()
/// on their FocusNode once, in initState, to opt into hiding the bar
/// while they're focused; nothing else needs to change at any call site.
final ValueNotifier<bool> appSuppressKeyboardDoneBarNotifier = ValueNotifier<bool>(false);

/// Attach to a single-line field's FocusNode (one that already has its own
/// native TextInputAction.done key) so the ambient KeyboardDoneBar hides
/// itself while that field is focused, instead of showing alongside the
/// native done key. Call once, in initState, right after creating the
/// FocusNode -- no other changes needed at the call site.
void suppressKeyboardBarWhileFocused(FocusNode node) {
  node.addListener(() {
    appSuppressKeyboardDoneBarNotifier.value = node.hasFocus;
  });
}

// ── Flash-of-wrong-content fix, rollout to remaining fields ──────────────
// Same pattern as appIsNestOwnerNotifier/appSeniorCheckedInTodayNotifier
// above, proven clean on-device (build 171). Each of these was previously
// declared independently, per-screen, as "bool _x = false;" -- a hardcoded
// guess corrected only after an async cache/network read finished, causing
// at least one wrong-content frame on every screen build. Resolved once in
// main.dart's _resolveInitialRoute() before any screen builds; screens read
// the notifier's value at field declaration instead of guessing, and write
// the real value back once their own live check resolves.

/// isSenior was independently duplicated across 5 screens (family_feed,
/// legacy, safety, send, setup), all deriving it from the same
/// prefs.getString('user_role') key -- one shared notifier fixes the flash
/// in all 5 at once instead of five separate patches.
final ValueNotifier<bool> appIsSeniorNotifier = ValueNotifier<bool>(false);

final ValueNotifier<bool> appIsGuestNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> appHasRealPostNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> appHasSentStoriesNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> appIsVipMemberNotifier = ValueNotifier<bool>(false);

/// Date-scoped like appSeniorCheckedInTodayNotifier -- only meaningful for
/// today, resolved from the same cached_checkin_* prefs family.
final ValueNotifier<bool> appSeniorMedsTakenTodayNotifier = ValueNotifier<bool>(false);

/// Found while investigating D Von's screenshot (build 172, Aug 15): the
/// floating "I'm Good" button's own visibility flag (_isGoodTodaySent) had
/// the exact same hardcoded-false-default pattern as everything else in
/// this section, but got missed in the original rollout since it's driven
/// by a separate local-only prefs key (good_today_*) rather than the
/// cached_checkin_* family the other notifiers share. Date-scoped like the
/// others; resolved from the same key family_feed_screen.dart itself
/// writes to (see _todayKey() there for the exact date-string format this
/// must match).
final ValueNotifier<bool> appIsGoodTodaySentNotifier = ValueNotifier<bool>(false);

/// Own display name -- was independently duplicated across 7 screens
/// (setup, feed_top_bar, family_feed, send, safety, legacy, favs), every
/// one declaring "String _displayName = '';" and correcting it after its
/// own async SharedPreferences read finished -- the same flash-of-wrong-
/// content pattern as appIsSeniorNotifier above, just for a string and at
/// larger scale (7 duplicates instead of 5). Resolved once in main.dart's
/// _resolveInitialRoute() from the same preferred_name -> display_name
/// fallback chain every one of those screens already used independently.
final ValueNotifier<String> appDisplayNameNotifier = ValueNotifier<String>('');

/// The senior's name, as shown to family members (Home's pinned check-in
/// card, Safety's "This is what ___ sees" banner). Aug 25 2026: found
/// safety_screen was reading a 'senior_name' prefs key that is never
/// written anywhere in the app -- confirmed via full codebase search --
/// so it was blank on literally every first paint for every family
/// member, guaranteed, not just occasionally. family_feed_screen already
/// had a working cache under a different key (cached_checkin_senior_name,
/// written after its own live nest_members lookup resolves), so this
/// notifier is seeded from that real cache instead, and both screens now
/// share it -- the same one-shared-source-of-truth fix already applied to
/// appIsNestOwnerNotifier.
final ValueNotifier<String> appSeniorNameNotifier = ValueNotifier<String>('');

/// The senior's user ID, same cache key family as appSeniorNameNotifier
/// above (cached_checkin_senior_id, not cached_checkin_senior_name).
/// Found during the whole-app flash audit: family_feed_screen used this
/// ID, not the name, to decide whether the pinned check-in card shows at
/// all -- started at '' (card absent) and only became non-empty after
/// _loadData()'s async read finished, so the card appeared late on every
/// load instead of being there from the first frame when a senior exists.
final ValueNotifier<String> appSeniorUserIdNotifier = ValueNotifier<String>('');

// ── Aug 31 2026: whole-app flash audit, prompted by D Von finding the "I'm
// Good" button still flashing on a cold open even after Archive Nest Mode
// itself worked correctly. Turned out to be the same hardcoded-false-
// default pattern as everything above, just never brought into this
// notifier system -- three fields across Home, Safety, and Setup were each
// declaring their own local "bool _x = false/true;" and correcting it only
// after their own async read finished, exactly like every fix in this file
// already exists to prevent. Brought into the same system for the same
// reason: one resolved-before-first-frame source of truth, shared instead
// of duplicated.

/// Whether this nest has been archived into a memorial space (Archive Nest
/// Mode, built same day). Previously had no persisted cache at all --
/// family_feed_screen declared "bool _isNestArchived = false;" with
/// nothing backing it, so it was wrong on literally every load until its
/// own live Supabase fetch corrected it moments later; that's what caused
/// the "I'm Good" button flash D Von found. Safety and Setup each had
/// their own separate local copy too, meaning even after fixing one,
/// the other two could still disagree or flash independently. Now one
/// shared notifier, cached under cached_is_nest_archived (added to the
/// account-scoped wipe list in auth_service.dart), resolved before first
/// frame like everything else here.
final ValueNotifier<bool> appIsNestArchivedNotifier = ValueNotifier<bool>(false);

/// Whether the senior's meds-reminder nudge card should still show today
/// (separate from whether meds were actually taken). Was hardcoded true
/// at field declaration in family_feed_screen regardless of what the
/// person actually last set, while the real value it corrected to moments
/// later came from a date-scoped meds_reminder_* prefs key that already
/// existed -- this notifier just makes that existing value readable
/// synchronously instead of only after an async read.
final ValueNotifier<bool> appShowMedsReminderNotifier = ValueNotifier<bool>(true);

/// Whether a family nest owner has already shared their invite code.
/// Found via Pre-Ship Audit 1: the field default (true) and the real
/// prefs fallback (false) didn't even agree with each other, so this
/// flashed on every single first-ever load, not just returning users.
final ValueNotifier<bool> appInviteCodeSharedNotifier = ValueNotifier<bool>(true);

/// Whether the Daily Updates section (check-in/meds cards on Home) is
/// collapsed today. Sep 17 2026: caught this same session, on the same
/// project, right after the Aug 31 whole-app flash audit above -- the
/// widget that wraps this was built with its own local async
/// SharedPreferences read in initState() and a "_loaded" gate that
/// rendered nothing until it resolved, the exact anti-pattern every
/// notifier in this file exists to prevent. Brought into the same
/// system so it's resolved before first paint like everything else,
/// instead of popping in a beat after the rest of Home already has.
final ValueNotifier<bool> appDailyUpdatesCollapsedNotifier =
    ValueNotifier<bool>(false);

/// Sep 17 2026, same audit sweep: this senior's own real
/// check-in/meds-reminder preferences (set via the Setup screen toggle)
/// gate two pieces of real, functional UI on Home -- the floating "I'm
/// Good" button (appMyCheckinEnabledNotifier) and the actionable
/// "Daily Medications" prompt card (appMyMedsRemindersEnabledNotifier).
/// Both fields on Home defaulted to true at declaration, corrected only
/// after Home's own async Supabase fetch resolved -- so a senior who'd
/// actually turned either off would still see it flash on, then
/// disappear, every single load. Setup screen already caches both
/// under 'meds_reminders'/'daily_check_in' the moment they're toggled
/// (used to seed Setup's own fields instantly) -- Home just never read
/// that same cache. Seeded from it here instead of a hardcoded true.
final ValueNotifier<bool> appMyCheckinEnabledNotifier = ValueNotifier<bool>(true);
final ValueNotifier<bool> appMyMedsRemindersEnabledNotifier =
    ValueNotifier<bool>(true);

/// Whether this account has sent its first real message yet (gates
/// Messages' sample banner and placeholder card, same shape as
/// appHasRealPostNotifier/appHasSentStoriesNotifier above -- Messages just
/// never had a notifier for it, so it flashed real content behind a
/// placeholder on every load with no cache backing it at first paint.
final ValueNotifier<bool> appHasSentMessagesNotifier = ValueNotifier<bool>(false);

/// Maps the stored string to a TextScaler multiplier.
double textSizeToScale(String size) {
  switch (size) {
    case 'Large':
      return 1.2;
    case 'Extra Large':
      return 1.45;
    default:
      return 1.0; // Normal
  }
}

// ── Notifier resolution (Aug 31 2026, Pre-Ship Audit 1) ────────────────────
//
// Every notifier above except appTextScaleNotifier and
// appSuppressKeyboardDoneBarNotifier (device/UI preferences, not account
// data) used to be resolved ONLY here: inline, once, inside main.dart's
// _resolveInitialRoute(), which only ever runs at a true cold app launch.
// Only appDarkModeNotifier got a second, separate resolution -- patched
// directly into auth_service.dart's clearStaleAccountDataIfUserChanged()
// on Aug 21 2026, specifically because a warm sign-out/sign-in (no
// force-quit in between) never reaches _resolveInitialRoute() at all, so
// nothing was refreshing it for that scenario.
//
// Audit 1 (the cross-session state sweep) found that gap was never
// actually specific to dark_mode -- it applies to all 14 of these
// notifiers equally. The underlying SharedPreferences values were already
// being correctly wiped/reset on a genuine account switch (see the wipe
// list a few lines above clearStaleAccountDataIfUserChanged in
// auth_service.dart), but nothing told the notifiers themselves to
// re-read from that now-correct storage until the next cold start. Since
// almost every screen reads from these notifiers, not from prefs
// directly, that gap is the most likely real explanation for D Von's
// long-running "flash of old info from the previous account" reports
// during rapid multi-account testing.
//
// This function is that one resolution, extracted so it can be called
// from both places that need it: main.dart's cold-start path (unchanged
// behavior) and, new as of this fix, right after the storage wipe inside
// clearStaleAccountDataIfUserChanged() (the actual fix for a warm
// switch). Takes an already-obtained SharedPreferences instance rather
// than fetching its own, since both call sites already have one in scope.
Future<void> resolveAppNotifiersFromPrefs(SharedPreferences prefs) async {
  // Dark mode: follow the saved preference if one was ever set, else
  // follow system brightness -- same fallback this always had.
  final savedDarkMode = prefs.getBool('dark_mode');
  if (savedDarkMode != null) {
    appDarkModeNotifier.value = savedDarkMode;
  } else {
    final brightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    appDarkModeNotifier.value = brightness == Brightness.dark;
  }

  final savedNestName = prefs.getString('nest_name');
  if (savedNestName != null && savedNestName.isNotEmpty) {
    appNestNameNotifier.value = savedNestName;
  }

  appIsReturningUserNotifier.value = prefs.getBool('just_signed_out') ?? false;

  final cachedIsNestOwner = prefs.getBool('cached_is_nest_owner');
  if (cachedIsNestOwner != null) {
    appIsNestOwnerNotifier.value = cachedIsNestOwner;
  } else {
    final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
    appIsNestOwnerNotifier.value = !joinedViaInvite;
  }

  // Same date/nest scoping as before: only trust the cached checked-in/
  // meds-taken flags if they were cached for this same nest, today.
  final cachedCheckinNestId = prefs.getString('cached_checkin_nest_id') ?? '';
  final cachedCheckinDate = prefs.getString('cached_checkin_date') ?? '';
  final currentNestId = prefs.getString('nest_id') ?? '';
  final now = DateTime.now();
  final todayDateString =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  if (cachedCheckinNestId.isNotEmpty &&
      cachedCheckinNestId == currentNestId &&
      cachedCheckinDate == todayDateString) {
    appSeniorCheckedInTodayNotifier.value =
        prefs.getBool('cached_checkin_checked_in') ?? false;
    appSeniorMedsTakenTodayNotifier.value =
        prefs.getBool('cached_checkin_meds_taken') ?? false;
  } else {
    // On a genuine account switch, a stale nest/date match is impossible
    // (nest_id itself was just wiped), so these correctly fall back to
    // false here rather than carrying over the previous account's status.
    appSeniorCheckedInTodayNotifier.value = false;
    appSeniorMedsTakenTodayNotifier.value = false;
  }

  // Key format must match family_feed_screen.dart's _todayKey() exactly
  // (unpadded year_month_day) -- different from todayDateString above.
  final goodTodayKey = '${now.year}_${now.month}_${now.day}';
  appIsGoodTodaySentNotifier.value =
      prefs.getBool('good_today_$goodTodayKey') ?? false;

  appIsSeniorNotifier.value =
      (prefs.getString('user_role') ?? 'senior') == 'senior';
  appIsGuestNotifier.value = prefs.getBool('is_guest') ?? false;
  appHasRealPostNotifier.value = prefs.getBool('has_real_post') ?? false;
  appHasSentStoriesNotifier.value = prefs.getBool('has_sent_stories') ?? false;
  appIsVipMemberNotifier.value = prefs.getBool('cached_is_vip_member') ?? false;

  final cachedPreferredName = prefs.getString('preferred_name') ?? '';
  appDisplayNameNotifier.value = cachedPreferredName.isNotEmpty
      ? cachedPreferredName
      : (prefs.getString('display_name') ?? '');

  appSeniorNameNotifier.value =
      prefs.getString('cached_checkin_senior_name') ?? '';

  appSeniorUserIdNotifier.value =
      prefs.getString('cached_checkin_senior_id') ?? '';

  // Aug 31 2026: three new fields brought into this system, same reasoning
  // as everything above -- see each notifier's own doc comment for why.
  appIsNestArchivedNotifier.value =
      prefs.getBool('cached_is_nest_archived') ?? false;

  // Key format must match family_feed_screen.dart's _todayKey() exactly.
  final medsReminderKey = '${now.year}_${now.month}_${now.day}';
  appShowMedsReminderNotifier.value =
      prefs.getBool('meds_reminder_$medsReminderKey') ?? true;

  appInviteCodeSharedNotifier.value =
      prefs.getBool('invite_code_shared') ?? false;

  // Same reasoning as the Aug 31 batch above, caught same session.
  appDailyUpdatesCollapsedNotifier.value =
      prefs.getString('daily_updates_collapsed_date') == todayDateString;

  appMyCheckinEnabledNotifier.value = prefs.getBool('daily_check_in') ?? true;
  appMyMedsRemindersEnabledNotifier.value =
      prefs.getBool('meds_reminders') ?? true;

  appHasSentMessagesNotifier.value =
      prefs.getBool('has_sent_messages') ?? false;

  // Sep 17 2026: root-level fix. Every screen ultimately seeds its own
  // display name from appDisplayNameNotifier's value here, which until
  // now was set purely from local cache above (cachedPreferredName /
  // 'display_name'), never checked against the real database record
  // anywhere in the shared path. Confirmed live: a real, long-standing
  // senior account ("Popy," database totally correct and untouched)
  // displayed as a completely different, previously-tested account's
  // name ("Uncle Bob") on a device that still had that other account's
  // name cached locally. setup_screen.dart got a direct fix for this
  // first; this is the actual shared root, covering every other screen
  // (Home, Safety, Legacy, Favs, Send) that reads from the same cache
  // this function fills, without needing five more individual patches.
  //
  // Only acts when a real profile row genuinely comes back -- a null
  // result (no row at all) means this account is still mid-onboarding,
  // not yet fully created, and touching local cache in that state is
  // exactly the "wiped a fresh signup's own just-entered values" bug
  // documented on _accountScopedPrefsKeys in auth_service.dart. Fails
  // open on any error, same reasoning -- never block app startup on it.
  try {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      final realProfile = await Supabase.instance.client
          .from('user_profiles')
          .select('display_name, preferred_name')
          .eq('id', currentUser.id)
          .maybeSingle();
      if (realProfile != null) {
        final realName = (realProfile['display_name'] as String? ?? '').trim();
        final realPreferredName =
            (realProfile['preferred_name'] as String? ?? '').trim();
        final effectiveRealName =
            realPreferredName.isNotEmpty ? realPreferredName : realName;
        if (effectiveRealName.isNotEmpty) {
          appDisplayNameNotifier.value = effectiveRealName;
        }
        await prefs.setString('display_name', realName);
        await prefs.setString('preferred_name', realPreferredName);
      }
    }
  } catch (_) {}
}

// Sep 21 2026: D Von's direct, correct push -- "start downloading early
// and hope it finishes in time" isn't the real fix. The standard,
// first-principles way to guarantee zero placeholder flash for KNOWN
// content is simpler and more direct: don't show the screen until its
// images are actually ready. This is that gate, shared so it can be used
// two ways -- fired early and unawaited right when an invite code is
// verified (role_choice_screen.dart) for maximum head start, AND awaited
// with a timeout right before Home actually navigates into view
// (save_messages_prompt_screen.dart's _navigateToHome) as the real
// guarantee -- Home simply does not render until this either completes
// or hits its time cap, same as the app's existing branded-transition
// minimum-display-duration wait already does for the rest of this same
// moment. Only for Flow 3/4 (joining an established nest via invite
// code) -- the only two flows where the real photos already exist on
// the server before onboarding even starts.
Future<void> precacheNestImages(String nestId) async {
  try {
    final supabase = Supabase.instance.client;
    // Avatars are never a network image (emoji character or base64
    // bytes decoded locally via Image.memory() in
    // profile_photo_picker_screen.dart) -- nothing to precache there.
    // SECURITY DEFINER function since the person isn't a member of this
    // nest yet at this point -- same trust boundary as the invite-code
    // lookup itself (a verified code is what establishes the right to
    // preview this nest's photos here), and it filters out this nest's
    // audio/video posts, which share the same media_url column but a
    // different storage folder from actual photo posts.
    final rows = await supabase.rpc(
      'get_nest_preview_images',
      params: {'p_nest_id': nestId},
    ) as List;

    final futures = <Future<void>>[];
    for (final row in rows) {
      final url = row['media_url'] as String?;
      if (url == null || url.isEmpty) continue;
      final completer = Completer<void>();
      CachedNetworkImageProvider(url)
          .resolve(const ImageConfiguration())
          .addListener(
            ImageStreamListener(
              (_, __) {
                if (!completer.isCompleted) completer.complete();
              },
              onError: (_, __) {
                if (!completer.isCompleted) completer.complete();
              },
            ),
          );
      futures.add(completer.future);
    }
    await Future.wait(futures);
  } catch (e) {
    debugPrint('PRECACHE_NEST_IMAGES_ERROR: $e');
  }
}

