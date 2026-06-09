import 'package:flutter/material.dart';

import '../presentation/family_feed_screen/family_feed_screen.dart';
import '../presentation/role_choice_screen/role_choice_screen.dart';
import '../presentation/splash_screen/splash_screen.dart';
import '../presentation/senior_onboarding_screen/senior_onboarding_screen.dart';
import '../presentation/family_onboarding_screen/family_onboarding_screen.dart';
import '../presentation/send_screen/send_screen.dart';
import '../presentation/legacy_screen/legacy_screen.dart';
import '../presentation/favs_screen/favs_screen.dart';
import '../presentation/safety_screen/safety_screen.dart';
import '../presentation/setup_screen/setup_screen.dart';
import '../presentation/nest_role_after_invite_screen/nest_role_after_invite_screen.dart';
import '../presentation/subscribe_nest_screen/subscribe_nest_screen.dart';
import '../presentation/help_support_screen/help_support_screen.dart';
import '../presentation/privacy_policy_screen/privacy_policy_screen.dart';
import '../presentation/save_messages_prompt_screen/save_messages_prompt_screen.dart';
import '../presentation/profile_photo_picker_screen/profile_photo_picker_screen.dart';
import '../presentation/notifications_screen/notifications_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String splashScreen = '/splash-screen';
  static const String roleChoiceScreen = '/role-choice-screen';
  static const String familyFeedScreen = '/family-feed-screen';
  static const String seniorOnboardingScreen = '/senior-onboarding-screen';
  static const String familyOnboardingScreen = '/family-onboarding-screen';
  static const String sendScreen = '/send-screen';
  static const String legacyScreen = '/legacy-screen';
  static const String favsScreen = '/favs-screen';
  static const String safetyScreen = '/safety-screen';
  static const String setupScreen = '/setup-screen';
  static const String nestRoleAfterInviteScreen =
      '/nest-role-after-invite-screen';
  static const String subscribeNestScreen = '/subscribe-nest-screen';
  static const String helpSupportScreen = '/help-support-screen';
  static const String privacyPolicyScreen = '/privacy-policy-screen';
  static const String saveMessagesPromptScreen = '/save-messages-prompt-screen';
  static const String profilePhotoPickerScreen = '/profile-photo-picker-screen';
  static const String notificationsScreen = '/notifications-screen';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const SplashScreen(),
    splashScreen: (context) => const SplashScreen(),
    roleChoiceScreen: (context) => const RoleChoiceScreen(),
    familyFeedScreen: (context) => const FamilyFeedScreen(),
    seniorOnboardingScreen: (context) => const SeniorOnboardingScreen(),
    familyOnboardingScreen: (context) => const FamilyOnboardingScreen(),
    sendScreen: (context) => const SendScreen(),
    legacyScreen: (context) => const LegacyScreen(),
    favsScreen: (context) => const FavsScreen(),
    safetyScreen: (context) => const SafetyScreen(),
    setupScreen: (context) => const SetupScreen(),
    nestRoleAfterInviteScreen: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      return NestRoleAfterInviteScreen(
        inviteCode: args?['inviteCode'] as String? ?? '',
      );
    },
    subscribeNestScreen: (context) => const SubscribeNestScreen(),
    helpSupportScreen: (context) => const HelpSupportScreen(),
    privacyPolicyScreen: (context) => const PrivacyPolicyScreen(),
    saveMessagesPromptScreen: (context) => const SaveMessagesPromptScreen(),
    profilePhotoPickerScreen: (context) => const ProfilePhotoPickerScreen(),
    notificationsScreen: (context) => const NotificationsScreen(),
  };
}
