import 'package:flutter/material.dart';
import '../../screens/auth_screen.dart';
import '../../screens/main_navigation.dart';
import '../../screens/splash_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/notifications_screen.dart';
import '../../screens/notification_preferences_screen.dart';
import '../../screens/wallet_screen.dart';
import '../../screens/payment_screen.dart';
import '../../screens/dispute_screen.dart';
import '../../screens/referral_screen.dart';
import '../../screens/subscription_screen.dart';
import '../../screens/commission_screen.dart';
import '../../screens/enrollments_screen.dart';
import '../../screens/courses_screen.dart';
import '../../screens/skill_share_screen.dart';
import '../../screens/portfolio_screen.dart';
import '../../screens/nid_screen.dart';
import '../../screens/background_check_screen.dart';
import '../../screens/provider_online_screen.dart';
import '../../screens/provider_dashboard_screen.dart';
import '../../screens/provider_onboarding_screen.dart';
import '../../screens/legal_onboarding_screen.dart';
import '../../screens/orders_screen.dart';
import '../../screens/grocery_screen.dart';
import '../../screens/messages_screen.dart';
import '../../screens/forgot_password_screen.dart';
import '../../screens/agent_screen.dart';
import '../../screens/mess_screen.dart';
import '../../screens/my_match_requests_screen.dart';
import '../../screens/scrap_screen.dart';
import '../../screens/meal_groups_list_screen.dart';

class AppRoutes {
  // ── Auth ──────────────────────────────────────────────────────────
  static const splash             = '/';
  static const auth               = '/auth';
  static const otp                = '/auth/otp';
  static const forgotPassword     = '/auth/forgot-password';

  // ── Main ─────────────────────────────────────────────────────────
  static const home               = '/home';
  static const profile            = '/profile';
  static const messages           = '/messages';
  static const orders             = '/orders';

  // ── Notifications ────────────────────────────────────────────────
  static const notifications      = '/notifications';
  static const notifPreferences   = '/notifications/preferences';

  // ── Finance ──────────────────────────────────────────────────────
  static const wallet             = '/wallet';
  static const payments           = '/payments';
  static const commission         = '/commission';

  // ── User Services ────────────────────────────────────────────────
  static const subscription       = '/subscription';
  static const referral           = '/referral';
  static const disputes           = '/disputes';
  static const myMatchRequests    = '/match-requests';

  // ── Grocery ──────────────────────────────────────────────────────
  static const grocery            = '/grocery';
  static const groceryCheckout    = '/grocery/checkout';

  // ── Commerce ─────────────────────────────────────────────────────
  static const scrap              = '/scrap';
  static const mess               = '/mess';
  static const mealGroups         = '/meal-groups';

  // ── Learning ─────────────────────────────────────────────────────
  static const courses            = '/courses';
  static const myEnrollments      = '/courses/enrollments';

  // ── Skill Share ──────────────────────────────────────────────────
  static const skillShare         = '/skill-share';

  // ── Provider ─────────────────────────────────────────────────────
  static const providerDashboard  = '/provider/dashboard';
  static const providerOnboarding = '/provider/onboarding';
  static const legalOnboarding    = '/provider/legal-onboarding';
  static const providerOnline     = '/provider/online';
  static const portfolio          = '/provider/portfolio';
  static const nid                = '/provider/nid';
  static const backgroundCheck    = '/provider/background-check';
  static const agent              = '/agent';

  // ── Route map for MaterialApp.routes ─────────────────────────────
  static Map<String, WidgetBuilder> get routes => {
    splash:             (_) => const SplashScreen(),
    auth:               (_) => const AuthScreen(),
    forgotPassword:     (_) => const ForgotPasswordScreen(),
    home:               (_) => const MainNavigation(),
    profile:            (_) => const ProfileScreen(),
    messages:           (_) => const MessagesScreen(),
    orders:             (_) => const OrdersScreen(),
    notifications:      (_) => const NotificationListScreen(),
    notifPreferences:   (_) => const NotificationPreferencesScreen(),
    wallet:             (_) => const WalletScreen(),
    payments:           (_) => const PaymentScreen(),
    commission:         (_) => const CommissionScreen(),
    subscription:       (_) => const SubscriptionScreen(),
    referral:           (_) => const ReferralScreen(),
    disputes:           (_) => const DisputeScreen(),
    myMatchRequests:    (_) => const MyMatchRequestsScreen(),
    grocery:            (_) => const GroceryScreen(),
    scrap:              (_) => const ScrapScreen(),
    mess:               (_) => const MessScreen(),
    mealGroups:         (_) => const MealGroupsListScreen(),
    courses:            (_) => const CoursesScreen(),
    myEnrollments:      (_) => const EnrollmentsScreen(),
    skillShare:         (_) => const SkillShareScreen(),
    providerDashboard:  (_) => const ProviderDashboardScreen(),
    providerOnboarding: (_) => const ProviderOnboardingScreen(),
    legalOnboarding:    (_) => const LegalOnboardingScreen(),
    providerOnline:     (_) => const ProviderOnlineScreen(),
    portfolio:          (_) => const PortfolioScreen(),
    nid:                (_) => const NidScreen(),
    backgroundCheck:    (_) => const BackgroundCheckScreen(),
    agent:              (_) => const AgentScreen(),
  };
}
