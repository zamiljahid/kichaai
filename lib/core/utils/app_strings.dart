import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageNotifier extends ChangeNotifier {
  static const _prefKey = 'app_language';
  String _lang = 'bn';

  String get lang => _lang;
  bool get isBengali => _lang == 'bn';

  LanguageNotifier() {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString(_prefKey) ?? 'bn';
    notifyListeners();
  }

  Future<void> toggle() async {
    _lang = _lang == 'bn' ? 'en' : 'bn';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _lang);
    notifyListeners();
  }
}

class AppStrings {
  static AppStrings of(BuildContext context) {
    final lang = context.watch<LanguageNotifier>().lang;
    return AppStrings._(lang);
  }

  static AppStrings withLang(String lang) => AppStrings._(lang);

  final String _lang;
  AppStrings._(this._lang);

  String _s(String bn, String en) => _lang == 'bn' ? bn : en;

  // ── Auth ──────────────────────────────────────────────────────────
  String get login => _s('লগইন করুন', 'Login');
  String get register => _s('নিবন্ধন করুন', 'Register');
  String get logout => _s('লগআউট', 'Logout');
  String get loginTab => _s('লগইন', 'Login');
  String get registerTab => _s('নিবন্ধন', 'Register');
  String get welcomeBack => _s('স্বাগতম!', 'Welcome Back!');
  String get loginSubtitle => _s('আপনার অ্যাকাউন্টে লগইন করুন', 'Sign in to your account');
  String get createAccount => _s('নতুন অ্যাকাউন্ট', 'New Account');
  String get registerSubtitle => _s('আজই কিচাইতে যোগ দিন', 'Join Kichaai today');
  String get fullName => _s('পুরো নাম', 'Full Name');
  String get phone => _s('মোবাইল নম্বর', 'Mobile Number');
  String get password => _s('পাসওয়ার্ড', 'Password');
  String get forgotPassword => _s('পাসওয়ার্ড ভুলে গেছেন?', 'Forgot password?');
  String get loginWithGoogle => _s('Google দিয়ে লগইন', 'Login with Google');
  String get orDivider => _s('অথবা', 'or');
  String get customer => _s('সেবা গ্রহীতা', 'Customer');
  String get provider => _s('সেবাদাতা', 'Provider');

  // ── Home ──────────────────────────────────────────────────────────
  String get greeting => _s('আস-সালামু আলাইকুম 👋', 'As-salamu alaykum 👋');
  String get homeQuestion => _s('আপনার কী সেবা দরকার?', 'What service do you need?');
  String get searchHint => _s('সেবা খুঁজুন...', 'Search services...');
  String get filterLabel => _s('ফিল্টার', 'Filter');
  String get categories => _s('সেবা বিভাগ', 'Service Categories');
  String get topProviders => _s('শীর্ষ সেবাদাতা', 'Top Providers');
  String get viewAll => _s('সব দেখুন', 'View All');
  String get newRequest => _s('নতুন সেবার অনুরোধ করুন', 'Post a new service request');

  // ── Orders ────────────────────────────────────────────────────────
  String get myOrders => _s('আমার অর্ডার', 'My Orders');
  String get activeOrders => _s('সক্রিয়', 'Active');
  String get completedOrders => _s('সম্পন্ন', 'Completed');
  String get noOrders => _s('কোনো অর্ডার নেই', 'No orders found');
  String get cancel => _s('বাতিল', 'Cancel');
  String get track => _s('ট্র্যাক করুন', 'Track');
  String get cancelConfirm => _s('এই অর্ডারটি বাতিল করবেন?', 'Cancel this order?');
  String get yes => _s('হ্যাঁ', 'Yes');
  String get no => _s('না', 'No');

  // ── Messages ──────────────────────────────────────────────────────
  String get messages => _s('বার্তা', 'Messages');
  String get noMessages => _s('কোনো বার্তা নেই', 'No messages');
  String get typeMessage => _s('বার্তা লিখুন...', 'Type a message...');
  String get send => _s('পাঠান', 'Send');

  // ── Profile ───────────────────────────────────────────────────────
  String get profile => _s('প্রোফাইল', 'Profile');
  String get editProfile => _s('প্রোফাইল সম্পাদনা', 'Edit Profile');
  String get changePassword => _s('পাসওয়ার্ড পরিবর্তন', 'Change Password');
  String get myAddresses => _s('আমার ঠিকানা', 'My Addresses');
  String get addAddress => _s('নতুন ঠিকানা যোগ করুন', 'Add Address');
  String get saveChanges => _s('পরিবর্তন সংরক্ষণ', 'Save Changes');

  // ── General ───────────────────────────────────────────────────────
  String get loading => _s('লোড হচ্ছে...', 'Loading...');
  String get retry => _s('আবার চেষ্টা করুন', 'Retry');
  String get success => _s('সফল', 'Success');
  String get error => _s('ত্রুটি', 'Error');
  String get langToggle => _s('EN', 'বাং');

  // ── Error messages ────────────────────────────────────────────────
  String get errNetwork => _s(
    'ইন্টারনেট সংযোগ নেই। দয়া করে আবার চেষ্টা করুন।',
    'No internet connection. Please try again.',
  );
  String get errTimeout => _s(
    'সার্ভার সাড়া দিচ্ছে না। দয়া করে পরে চেষ্টা করুন।',
    'Server not responding. Please try later.',
  );
  String get errUnauthorized => _s(
    'সেশন মেয়াদ শেষ হয়েছে। আবার লগইন করুন।',
    'Session expired. Please login again.',
  );
  String get errForbidden => _s(
    'আপনার এই কাজের অনুমতি নেই।',
    'You do not have permission to do this.',
  );
  String get errNotFound => _s(
    'তথ্য পাওয়া যায়নি।',
    'Information not found.',
  );
  String get errServer => _s(
    'সার্ভারে সমস্যা হয়েছে। দয়া করে পরে চেষ্টা করুন।',
    'Server error. Please try later.',
  );
  String get errUnknown => _s(
    'একটি অপ্রত্যাশিত সমস্যা হয়েছে।',
    'An unexpected error occurred.',
  );
  String get errPhoneRequired => _s('মোবাইল নম্বর দিন', 'Enter mobile number');
  String get errPasswordRequired => _s('পাসওয়ার্ড দিন', 'Enter password');
  String get errNameRequired => _s('নাম দিন', 'Enter your name');
  String get errPasswordShort => _s('পাসওয়ার্ড কমপক্ষে ৬ অক্ষর হতে হবে', 'Password must be at least 6 characters');
  String get errLoginFailed => _s('মোবাইল নম্বর বা পাসওয়ার্ড ভুল', 'Incorrect phone or password');
  String get errRegisterFailed => _s('নিবন্ধন ব্যর্থ হয়েছে', 'Registration failed');
}
