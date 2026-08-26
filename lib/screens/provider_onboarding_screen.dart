import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'main_navigation.dart';
import 'legal_onboarding_screen.dart';
import 'commute_partner_onboarding_screen.dart';
import 'cook_provider_screen.dart';
import 'technician_onboarding_screen.dart';

// ── Step enum ─────────────────────────────────────────────────────

enum _OBStep { loading, selectService, documentUpload, submitting, success }

// Doc-type codes with bespoke UIs. Anything else (NID, SSC, HSC, VARSITY_ID,
// SKILL_CERT, and any future image types) falls back to the single-image picker.
//   PORTFOLIO    — toggle between multi-image upload and Drive/Dropbox link
//   EQUIPMENT    — multi-line text field; typed text itself is the fileUrl
//   EXPERIENCE   — numeric text field; typed number is the fileUrl
//   BSC_DIPLOMA  — single image + a "currently a student" checkbox that
//                  overrides the isRequired flag (see _DocEntry.blocksSubmit)
const _kDocPortfolio = 'PORTFOLIO';
const _kDocEquipment = 'EQUIPMENT';
const _kDocExperience = 'EXPERIENCE';
const _kDocBscDiploma = 'BSC_DIPLOMA';

// ── Main screen ───────────────────────────────────────────────────

class ProviderOnboardingScreen extends StatefulWidget {
  const ProviderOnboardingScreen({super.key});

  @override
  State<ProviderOnboardingScreen> createState() => _ProviderOnboardingScreenState();
}

class _ProviderOnboardingScreenState extends State<ProviderOnboardingScreen> {
  _OBStep _step = _OBStep.loading;
  List<Map<String, dynamic>> _serviceTypes = [];
  String? _selectedServiceTypeId;
  String? _selectedServiceTypeName;
  List<_DocEntry> _docEntries = [];
  String? _error;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { _step = _OBStep.loading; _error = null; });
    try {
      await Future.wait([_callBecomeProvider(), _loadServiceTypes()]);
      if (mounted) setState(() => _step = _OBStep.selectService);
    } catch (e) {
      if (mounted) setState(() { _step = _OBStep.selectService; _error = ApiClient.mapError(e).localized(_isBn); });
    }
  }

  Future<void> _callBecomeProvider() async {
    try {
      await AuthService.instance.becomeProvider();
      try {
        final user = await AuthService.instance.getCurrentUser();
        final ppid = user.providerProfileId;
        if (ppid != null && ppid.isNotEmpty) {
          await ApiClient.setAsProvider(ppid);
        }
      } catch (_) {}
    } catch (_) {} // may already be a provider — ignore
  }

  Future<void> _loadServiceTypes() async {
    final list = await OnboardingService.instance.getServiceTypes();
    if (mounted) setState(() => _serviceTypes = list);
  }

  Future<void> _onServiceSelected(String id, String name) async {
    // Technician needs a group + specialization + group-specific hard-stop gate before the
    // generic document requirements even make sense (they don't vary by group) — captured in
    // a dedicated screen first. Bail out to the select-service step if the user backs out.
    if (id == 'st_technician') {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const TechnicianOnboardingScreen()),
      );
      if (ok != true || !mounted) return;
    }
    // Cook and ride follow the same shape as technician: a dedicated screen captures the
    // service-specific extras (menu items / vehicle papers) that the generic document step
    // can't express, then the normal requirements + application flow continues. Before rides
    // moved onto dispatch these two SKIPPED the application entirely, which is precisely why
    // a verified cook or driver could never go online — nothing granted them the kind.
    if (id == 'st_cook') {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CookOnboardingScreen()),
      );
      if (ok != true || !mounted) return;
    }
    if (id == 'st_commute') {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CommutePartnerOnboardingScreen()),
      );
      if (ok != true || !mounted) return;
    }
    setState(() { _step = _OBStep.loading; _error = null; });
    try {
      final reqs = await OnboardingService.instance.getServiceTypeRequirements(id);
      final entries = reqs
          .where((r) => r['documentTypeId'] != null)
          .map((r) {
            final dt = (r['documentType'] as Map?) ?? const {};
            return _DocEntry(
              documentTypeId: r['documentTypeId'] as String,
              code: (dt['code'] ?? '').toString(),
              name: (dt['name'] ?? dt['code'] ?? (_isBn ? 'ডকুমেন্ট' : 'Document')).toString(),
              // Backend flag — but BSC_DIPLOMA overrides this with a checkbox
              // (see _DocEntry.blocksSubmit). Default true if the field is
              // missing so a partial backend response can't silently unblock.
              isRequired: r['isRequired'] as bool? ?? true,
            );
          })
          .toList();
      if (!mounted) return;
      setState(() {
        _selectedServiceTypeId = id;
        _selectedServiceTypeName = name;
        _docEntries = entries;
        _step = _OBStep.documentUpload;
      });
    } catch (e) {
      if (mounted) setState(() { _step = _OBStep.selectService; _error = ApiClient.mapError(e).localized(_isBn); });
    }
  }

  Future<void> _submit() async {
    if (_selectedServiceTypeId == null || _selectedServiceTypeName == null) return;
    setState(() { _step = _OBStep.submitting; _error = null; });
    try {
      final providerId = await ApiClient.getUserId();
      if (providerId == null || providerId.isEmpty) {
        throw Exception(_isBn ? 'সেশনের মেয়াদ শেষ হয়ে গেছে — আবার লগইন করুন' : 'Session expired — please log in again.');
      }
      final appId = await OnboardingService.instance.createApplication(
        providerId: providerId,
        serviceTypeId: _selectedServiceTypeId!,
        serviceTypeNameSnapshot: _selectedServiceTypeName!,
      );
      for (final entry in _docEntries) {
        for (final doc in entry.docsForSubmit()) {
          final documentId = await OnboardingService.instance.uploadDocument(
            providerId: providerId,
            documentTypeId: entry.documentTypeId,
            fileUrl: doc.fileUrl,
            originalFileName: doc.originalFileName,
            mimeType: doc.mimeType,
          );
          await OnboardingService.instance.attachDocument(appId, documentId);
        }
      }
      await OnboardingService.instance.submitApplication(appId);
      if (mounted) setState(() => _step = _OBStep.success);
    } catch (e) {
      if (mounted) setState(() { _step = _OBStep.documentUpload; _error = ApiClient.mapError(e).localized(_isBn); });
    }
  }

  void _resetForAnotherService() {
    setState(() {
      _step = _OBStep.selectService;
      _selectedServiceTypeId = null;
      _selectedServiceTypeName = null;
      _docEntries = [];
      _error = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x22EF4444),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x66EF4444)),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
                ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final title = _isBn
        ? switch (_step) {
            _OBStep.success => 'আবেদন সফল!',
            _OBStep.documentUpload => 'ডকুমেন্ট আপলোড',
            _OBStep.submitting => 'জমা হচ্ছে...',
            _ => 'সেবা নির্বাচন করুন',
          }
        : switch (_step) {
            _OBStep.success => 'Application Successful!',
            _OBStep.documentUpload => 'Document Upload',
            _OBStep.submitting => 'Submitting...',
            _ => 'Select a Service',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _step == _OBStep.documentUpload ? Icons.arrow_back_rounded : Icons.close_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
            onPressed: () {
              if (_step == _OBStep.documentUpload) {
                _resetForAnotherService();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _OBStep.loading:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppColors.deepBlue),
            const SizedBox(height: 16),
            Text(_isBn ? 'লোড হচ্ছে...' : 'Loading...', style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        );
      case _OBStep.submitting:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppColors.deepBlue),
            const SizedBox(height: 16),
            Text(_isBn ? 'আবেদন জমা হচ্ছে...' : 'Submitting application...', style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        );
      case _OBStep.success:
        return _buildSuccess();
      case _OBStep.selectService:
        return _ServiceSelectStep(
          serviceTypes: _serviceTypes,
          onSelect: _onServiceSelected,
          isBn: _isBn,
        );
      case _OBStep.documentUpload:
        return _DocumentUploadStep(
          serviceTypeId: _selectedServiceTypeId ?? '',
          serviceTypeName: _selectedServiceTypeName ?? '',
          entries: _docEntries,
          onChanged: () => setState(() {}),
          onSubmit: _submit,
          isBn: _isBn,
        );
    }
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: AppColors.blueGradient,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.deepBlue.withValues(alpha: 0.5), blurRadius: 30)],
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.ivory, size: 52),
            ).animate().scale(duration: 500.ms, curve: Curves.elasticOut).fadeIn(),
            const SizedBox(height: 32),
            Text(
              _isBn ? 'আবেদন সফলভাবে জমা হয়েছে!' : 'Application submitted successfully!',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 12),
            Text(
              _isBn ? 'Admin যাচাই করলে আপনি notification পাবেন।' : 'You\'ll get a notification once admin reviews it.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ).animate(delay: 500.ms).fadeIn(),
            const SizedBox(height: 48),
            GlassButton(
              label: _isBn ? 'ড্যাশবোর্ডে ফিরুন' : 'Back to Dashboard',
              icon: Icons.dashboard_rounded,
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainNavigation()),
                (_) => false,
              ),
            ).animate(delay: 700.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 16),
            GlassButton(
              label: _isBn ? 'আরো একটি সেবা যোগ করুন' : 'Add Another Service',
              icon: Icons.add_rounded,
              isOutlined: true,
              onPressed: _resetForAnotherService,
            ).animate(delay: 850.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 16),
            GlassButton(
              label: _isBn ? 'আইনজীবী হিসেবে যুক্ত হন' : 'Join as a Lawyer',
              icon: Icons.gavel_rounded,
              isOutlined: true,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalOnboardingScreen()),
              ),
            ).animate(delay: 1000.ms).fadeIn().slideY(begin: 0.2),
          ],
        ),
      ),
    );
  }
}

// ── Service selection grid (single-select, tap = navigate) ─────────

class _ServiceSelectStep extends StatelessWidget {
  final List<Map<String, dynamic>> serviceTypes;
  final void Function(String id, String name) onSelect;
  final bool isBn;

  const _ServiceSelectStep({required this.serviceTypes, required this.onSelect, required this.isBn});

  @override
  Widget build(BuildContext context) {
    if (serviceTypes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.grid_view_rounded, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 16),
          Text(isBn ? 'সেবার তালিকা পাওয়া যায়নি' : 'No services found', style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
            ),
            // Regular API-driven services plus lawyer, which is the one track that still has no
            // onboarding application at all (dispatch grants it from ProviderProfile.legalRole
            // instead). Cook and ride used to be pinned here too, but now come from the API list
            // like everything else — their dedicated screens run from _onServiceSelected so they
            // also create a real application, which is what lets them go online.
            itemCount: serviceTypes.length + 1,
            itemBuilder: (context, i) {
              if (i < serviceTypes.length) {
                final s = serviceTypes[i];
                final id = s['id'] as String? ?? '';
                final icon = s['icon'] as String? ?? '🔧';
                final name = s['name'] as String? ?? '';
                final nameEn = s['nameEn'] as String? ?? '';
                return _ServiceTile(icon: icon, name: name, nameEn: nameEn, onTap: () => onSelect(id, name), delayIndex: i);
              }
              return _ServiceTile(
                icon: '⚖️',
                name: isBn ? 'আইনজীবী হিসেবে যুক্ত হন' : 'Join as a Lawyer',
                nameEn: 'Lawyer',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalOnboardingScreen())),
                delayIndex: i,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final String icon;
  final String name;
  final String nameEn;
  final VoidCallback onTap;
  final int delayIndex;

  const _ServiceTile({required this.icon, required this.name, required this.nameEn, required this.onTap, required this.delayIndex});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder, width: 1.5),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              nameEn,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: 40 * delayIndex)).fadeIn(duration: 250.ms).slideY(begin: 0.08);
  }
}

// ── Document upload step (generic, driven by requirements) ────────

class _DocumentUploadStep extends StatelessWidget {
  final String serviceTypeId;
  final String serviceTypeName;
  final List<_DocEntry> entries;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;
  final bool isBn;

  const _DocumentUploadStep({
    required this.serviceTypeId,
    required this.serviceTypeName,
    required this.entries,
    required this.onChanged,
    required this.onSubmit,
    required this.isBn,
  });

  int get _missingCount => entries.where((e) => e.blocksSubmit).length;
  bool get _anyBusy => entries.any((e) => e.isBusy);
  bool get _canSubmit => entries.isNotEmpty && _missingCount == 0 && !_anyBusy;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isBn ? 'এই সেবার জন্য কোনো ডকুমেন্ট প্রয়োজন নেই।' : 'No documents are required for this service.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text(
                  serviceTypeName,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              ...entries.map((e) => _DocCard(
                    entry: e,
                    serviceTypeId: serviceTypeId,
                    onChanged: onChanged,
                    isBn: isBn,
                  )),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: GlassButton(
            label: _canSubmit
                ? (isBn ? 'জমা দিন' : 'Submit')
                : _anyBusy
                    ? (isBn ? 'অপেক্ষা করুন...' : 'Please wait...')
                    : _missingCount > 0
                        ? (isBn ? '$_missingCount টি ডকুমেন্ট বাকি আছে' : '$_missingCount document(s) remaining')
                        : (isBn ? 'জমা দিন' : 'Submit'),
            icon: _canSubmit ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
            onPressed: _canSubmit ? () async => await onSubmit() : null,
          ),
        ),
      ],
    );
  }
}

// ── Per-document card (branches on code) ──────────────────────────

class _DocCard extends StatelessWidget {
  final _DocEntry entry;
  final String serviceTypeId;
  final VoidCallback onChanged;
  final bool isBn;

  const _DocCard({required this.entry, required this.serviceTypeId, required this.onChanged, required this.isBn});

  // Show the "ঐচ্ছিক" badge for genuinely-optional codes. BSC_DIPLOMA is
  // excluded — its optionality is controlled by the in-card checkbox, not the
  // isRequired flag, so a badge would mislead.
  bool get _showOptionalBadge => !entry.isRequired && entry.code != _kDocBscDiploma;

  @override
  Widget build(BuildContext context) {
    final body = switch (entry.code) {
      _kDocPortfolio => _PortfolioBody(entry: entry, onChanged: onChanged, isBn: isBn),
      _kDocEquipment => _EquipmentBody(entry: entry, serviceTypeId: serviceTypeId, onChanged: onChanged, isBn: isBn),
      _kDocExperience => _ExperienceBody(entry: entry, onChanged: onChanged, isBn: isBn),
      _kDocBscDiploma => _BscDiplomaBody(entry: entry, onChanged: onChanged, isBn: isBn),
      _ => _SingleImageBody(entry: entry, onChanged: onChanged, isBn: isBn),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: entry.isSatisfied ? AppColors.deepBlue : AppColors.glassBorder,
          width: entry.isSatisfied ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.isSatisfied ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                color: entry.isSatisfied ? AppColors.deepBlue : AppColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (_showOptionalBadge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Text(
                    isBn ? 'ঐচ্ছিক' : 'Optional',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

// ── Single-image doc body (NID and any other single-image type) ──

class _SingleImageBody extends StatelessWidget {
  final _DocEntry entry;
  final VoidCallback onChanged;
  final bool isBn;

  const _SingleImageBody({required this.entry, required this.onChanged, required this.isBn});

  Future<void> _pick(BuildContext context) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f == null) return;
    entry.uploading = true;
    onChanged();
    try {
      final upload = await _uploadFile(f);
      entry.files
        ..clear()
        ..add(upload);
    } catch (e) {
      if (context.mounted) _snack(context, ApiClient.mapError(e).localized(isBn));
    } finally {
      entry.uploading = false;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = entry.files.isNotEmpty ? entry.files.first : null;
    return _ImagePickBox(
      hint: isBn ? 'ট্যাপ করে ছবি বেছে নিন' : 'Tap to choose a photo',
      preview: file?.previewBytes,
      isBusy: entry.uploading,
      onTap: () => _pick(context),
      isBn: isBn,
    );
  }
}

// ── Portfolio doc body — toggle between multi-image and link ─────

class _PortfolioBody extends StatelessWidget {
  final _DocEntry entry;
  final VoidCallback onChanged;
  final bool isBn;

  const _PortfolioBody({required this.entry, required this.onChanged, required this.isBn});

  Future<void> _pick(BuildContext context) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f == null) return;
    entry.uploading = true;
    onChanged();
    try {
      final upload = await _uploadFile(f);
      entry.files.add(upload);
    } catch (e) {
      if (context.mounted) _snack(context, ApiClient.mapError(e).localized(isBn));
    } finally {
      entry.uploading = false;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeToggle(
          useLink: entry.useLink,
          onChanged: (v) {
            entry.useLink = v;
            onChanged();
          },
          isBn: isBn,
        ),
        const SizedBox(height: 12),
        if (entry.useLink)
          TextFormField(
            initialValue: entry.linkUrl,
            onChanged: (v) {
              entry.linkUrl = v;
              onChanged();
            },
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Google Drive / Dropbox link',
              prefixIcon: Icon(Icons.link_rounded, color: AppColors.textMuted, size: 20),
            ),
          )
        else
          _MultiImageGrid(
            files: entry.files,
            isBusy: entry.uploading,
            onAdd: () => _pick(context),
            onRemove: (i) {
              entry.files.removeAt(i);
              onChanged();
            },
          ),
      ],
    );
  }
}

// ── Experience doc body — digits only; typed number becomes the fileUrl ─

class _ExperienceBody extends StatelessWidget {
  final _DocEntry entry;
  final VoidCallback onChanged;
  final bool isBn;

  const _ExperienceBody({required this.entry, required this.onChanged, required this.isBn});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: entry.linkUrl,
      onChanged: (v) {
        entry.linkUrl = v;
        onChanged();
      },
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: isBn ? 'কত বছরের অভিজ্ঞতা?' : 'How many years of experience?',
        prefixIcon: const Icon(Icons.timelapse_rounded, color: AppColors.textMuted, size: 20),
      ),
    );
  }
}

// ── BSc/Diploma doc body — image picker + "currently studying" checkbox ─

class _BscDiplomaBody extends StatelessWidget {
  final _DocEntry entry;
  final VoidCallback onChanged;
  final bool isBn;

  const _BscDiplomaBody({required this.entry, required this.onChanged, required this.isBn});

  Future<void> _pick(BuildContext context) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f == null) return;
    entry.uploading = true;
    onChanged();
    try {
      final upload = await _uploadFile(f);
      entry.files
        ..clear()
        ..add(upload);
    } catch (e) {
      if (context.mounted) _snack(context, ApiClient.mapError(e).localized(isBn));
    } finally {
      entry.uploading = false;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            entry.currentlyStudying = !entry.currentlyStudying;
            onChanged();
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  entry.currentlyStudying
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: entry.currentlyStudying ? AppColors.deepBlue : AppColors.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isBn
                        ? 'আমি বর্তমানে বিশ্ববিদ্যালয়ে অধ্যয়নরত (এখনো সার্টিফিকেট নেই)'
                        : 'I am currently studying at university (no certificate yet)',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!entry.currentlyStudying) ...[
          const SizedBox(height: 10),
          _ImagePickBox(
            hint: isBn ? 'ট্যাপ করে ছবি বেছে নিন' : 'Tap to select an image',
            preview: entry.files.isNotEmpty ? entry.files.first.previewBytes : null,
            isBusy: entry.uploading,
            isBn: isBn,
            onTap: () => _pick(context),
          ),
        ],
      ],
    );
  }
}

// ── Equipment doc body — structured per-category dropdowns ────────
// Fetches the taxonomy once on mount, filters cinematographer-only categories
// for photographer applicants, and serializes selections to a Bengali string
// that becomes the doc's fileUrl at submit time.

class _EquipmentBody extends StatefulWidget {
  final _DocEntry entry;
  final String serviceTypeId;
  final VoidCallback onChanged;
  final bool isBn;

  const _EquipmentBody({
    required this.entry,
    required this.serviceTypeId,
    required this.onChanged,
    required this.isBn,
  });

  @override
  State<_EquipmentBody> createState() => _EquipmentBodyState();
}

class _EquipmentBodyState extends State<_EquipmentBody> {
  EquipmentTaxonomy? _tax;
  bool _loading = true;
  String? _loadError;

  bool get _isCinematographer => widget.serviceTypeId == 'st_cinematographer';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final t = await CatalogService.instance.getEquipmentTaxonomy();
      if (!mounted) return;
      setState(() {
        _tax = t;
        _loading = false;
      });
      _rebuildLinkUrl(); // rehydrate serialization from any pre-existing state
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = ApiClient.mapError(e).localized(widget.isBn);
        _loading = false;
      });
    }
  }

  _EqCategorySelection _selFor(String categoryCode) {
    return widget.entry.equipment.putIfAbsent(categoryCode, () => _EqCategorySelection());
  }

  void _rebuildLinkUrl() {
    final tax = _tax;
    if (tax == null) return;
    final lines = <String>[];
    for (final cat in tax.tree) {
      if (cat.cinematographerOnly && !_isCinematographer) continue;
      final sel = widget.entry.equipment[cat.code];
      if (sel == null) continue;
      final display = _displayFor(cat, sel);
      if (display != null && display.isNotEmpty) {
        lines.add('${cat.bn}: $display');
      }
    }
    widget.entry.linkUrl = lines.join('\n');
  }

  /// Human-readable value for one category's current selection.
  /// Returns null when the category has no meaningful answer yet.
  String? _displayFor(EquipmentCategory cat, _EqCategorySelection sel) {
    if (cat.multiSelect) {
      if (sel.multi.isEmpty) return null;
      // "নেই" is mutually exclusive with real items (enforced in _buildMulti),
      // so if it's in the set the answer is simply "none".
      if (sel.multi.any((c) => c.endsWith('_NONE'))) return 'নেই';
      final parts = <String>[];
      for (final code in sel.multi) {
        if (code.endsWith('_OTHER')) {
          final t = sel.other.trim();
          if (t.isNotEmpty) parts.add(t);
        } else {
          final item = _itemByCode(cat, code);
          if (item != null) parts.add(item.bn);
        }
      }
      return parts.isEmpty ? null : parts.join(', ');
    }
    // single-select
    final code = sel.single;
    if (code == null || code.isEmpty) return null;
    if (code.endsWith('_OTHER')) {
      final t = sel.other.trim();
      return t.isEmpty ? null : t;
    }
    if (code.endsWith('_NONE')) return 'নেই';
    return _itemByCode(cat, code)?.bn;
  }

  EquipmentItem? _itemByCode(EquipmentCategory cat, String code) {
    for (final it in cat.items) {
      if (it.code == code) return it;
    }
    return null;
  }

  void _onSelectionChanged() {
    _rebuildLinkUrl();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue),
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isBn ? 'সরঞ্জাম তালিকা লোড করা যায়নি: $_loadError' : 'Could not load equipment list: $_loadError',
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _loadError = null;
              });
              _fetch();
            },
            child: Text(widget.isBn ? 'আবার চেষ্টা করুন' : 'Try again', style: const TextStyle(color: AppColors.deepBlue)),
          ),
        ],
      );
    }

    final tax = _tax!;
    final visible = tax.tree.where((c) => !c.cinematographerOnly || _isCinematographer).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < visible.length; i++) ...[
          _buildCategory(visible[i]),
          if (i < visible.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildCategory(EquipmentCategory cat) {
    final sel = _selFor(cat.code);
    final showOther = cat.multiSelect
        ? sel.multi.any((c) => c.endsWith('_OTHER'))
        : (sel.single?.endsWith('_OTHER') ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isBn ? cat.bn : cat.en,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        if (cat.multiSelect) _buildMulti(cat, sel) else _buildSingle(cat, sel),
        if (showOther) ...[
          const SizedBox(height: 8),
          _buildOtherField(cat, sel),
        ],
      ],
    );
  }

  Widget _buildSingle(EquipmentCategory cat, _EqCategorySelection sel) {
    return DropdownButtonFormField<String>(
      initialValue: sel.single,
      isExpanded: true,
      dropdownColor: AppColors.bgMid,
      icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textMuted),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.isBn ? 'বেছে নিন' : 'Select',
      ),
      items: cat.items
          .map((it) => DropdownMenuItem<String>(
                value: it.code,
                child: Text(widget.isBn ? it.bn : it.en, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) {
        sel.single = v;
        if (v == null || !v.endsWith('_OTHER')) sel.other = '';
        _onSelectionChanged();
      },
    );
  }

  // Compact tap-to-open picker (was a large always-visible chip grid — with
  // real equipment models the list is now too long to show inline).
  Widget _buildMulti(EquipmentCategory cat, _EqCategorySelection sel) {
    final labels = <String>[];
    for (final code in sel.multi) {
      if (code.endsWith('_OTHER')) {
        final t = sel.other.trim();
        if (t.isNotEmpty) labels.add(t);
      } else {
        final item = _itemByCode(cat, code);
        if (item != null) labels.add(widget.isBn ? item.bn : item.en);
      }
    }
    final displayText = labels.join(', ');

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openMultiPicker(cat, sel),
      child: InputDecorator(
        isEmpty: displayText.isEmpty,
        decoration: InputDecoration(
          hintText: widget.isBn ? 'বেছে নিন (একাধিক)' : 'Select (multiple)',
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textMuted),
        ),
        child: Text(
          displayText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
      ),
    );
  }

  Future<void> _openMultiPicker(EquipmentCategory cat, _EqCategorySelection sel) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgMid,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.glassBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.isBn ? cat.bn : cat.en,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isBn ? 'একাধিক বেছে নিতে পারবেন' : 'You can select multiple',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: cat.items.map((it) {
                          final active = sel.multi.contains(it.code);
                          return CheckboxListTile(
                            value: active,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.deepBlue,
                            checkColor: AppColors.ivory,
                            title: Text(
                              widget.isBn ? it.bn : it.en,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            ),
                            onChanged: (v) {
                              setSheetState(() {
                                if (v == true) {
                                  // "নেই" is mutually exclusive with real items.
                                  if (it.code.endsWith('_NONE')) {
                                    sel.multi.clear();
                                    sel.other = '';
                                  } else {
                                    sel.multi.removeWhere((c) => c.endsWith('_NONE'));
                                  }
                                  sel.multi.add(it.code);
                                } else {
                                  sel.multi.remove(it.code);
                                  if (it.code.endsWith('_OTHER')) sel.other = '';
                                }
                              });
                              _onSelectionChanged();
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          widget.isBn ? 'হয়েছে' : 'Done',
                          style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildOtherField(EquipmentCategory cat, _EqCategorySelection sel) {
    return TextFormField(
      initialValue: sel.other,
      onChanged: (v) {
        sel.other = v;
        _onSelectionChanged();
      },
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: cat.multiSelect
            ? (widget.isBn ? 'অন্যান্য লেন্সের বিবরণ লিখুন' : 'Enter other lens details')
            : (widget.isBn ? '${cat.bn} মডেলের নাম লিখুন' : 'Enter ${cat.en} model name'),
        prefixIcon: const Icon(Icons.edit_rounded, color: AppColors.textMuted, size: 20),
      ),
    );
  }
}

class _EqCategorySelection {
  String? single;
  final Set<String> multi = {};
  String other = '';
}

class _ModeToggle extends StatelessWidget {
  final bool useLink;
  final void Function(bool) onChanged;
  final bool isBn;

  const _ModeToggle({required this.useLink, required this.onChanged, required this.isBn});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: active ? AppColors.blueGradient : null,
                color: active ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? AppColors.ivory : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          seg(isBn ? 'ছবি আপলোড' : 'Upload image', !useLink, () => onChanged(false)),
          seg(isBn ? 'লিংক দিন' : 'Give a link', useLink, () => onChanged(true)),
        ],
      ),
    );
  }
}

// ── Reusable image widgets (bytes-based, work on web + mobile) ────

class _ImagePickBox extends StatelessWidget {
  final String hint;
  final Uint8List? preview;
  final bool isBusy;
  final bool isBn;
  final VoidCallback onTap;

  const _ImagePickBox({
    required this.hint,
    required this.preview,
    required this.isBusy,
    required this.isBn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: preview != null ? AppColors.deepBlue : AppColors.glassBorder,
            width: 1.5,
          ),
        ),
        child: isBusy
            ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue, strokeWidth: 2))
            : preview != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      children: [
                        Positioned.fill(child: Image.memory(preview!, fit: BoxFit.cover)),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.deepBlue, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              isBn ? 'পরিবর্তন করুন' : 'Change',
                              style: const TextStyle(color: AppColors.ivory, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_upload_outlined, color: AppColors.textMuted, size: 32),
                      const SizedBox(height: 8),
                      Text(hint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
      ),
    );
  }
}

class _MultiImageGrid extends StatelessWidget {
  final List<_UploadedFile> files;
  final bool isBusy;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  const _MultiImageGrid({
    required this.files,
    required this.isBusy,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...files.asMap().entries.map((e) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(e.value.previewBytes, width: 80, height: 80, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemove(e.key),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ],
            )),
        if (files.length < 10)
          GestureDetector(
            onTap: isBusy ? null : onAdd,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: isBusy
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue),
                      ),
                    )
                  : const Icon(Icons.add_rounded, color: AppColors.textMuted, size: 28),
            ),
          ),
      ],
    );
  }
}

// ── State + helpers ───────────────────────────────────────────────

class _UploadedFile {
  final String fileUrl;
  final String fileName;
  final String mimeType;
  final Uint8List previewBytes;

  _UploadedFile({
    required this.fileUrl,
    required this.fileName,
    required this.mimeType,
    required this.previewBytes,
  });
}

class _DocEntry {
  final String documentTypeId;
  final String code;
  final String name;
  final bool isRequired;

  final List<_UploadedFile> files = [];
  String linkUrl = ''; // shared field: portfolio link, equipment serialized text, experience years
  bool useLink = false; // portfolio-only toggle
  bool uploading = false;
  bool currentlyStudying = false; // BSC_DIPLOMA-only checkbox

  /// EQUIPMENT-only structured state, keyed by category code (CAMERA, LENS, …).
  /// The serialized human-readable string is mirrored into [linkUrl] on every
  /// change so the submit path stays generic.
  final Map<String, _EqCategorySelection> equipment = {};

  _DocEntry({
    required this.documentTypeId,
    required this.code,
    required this.name,
    required this.isRequired,
  });

  bool get isBusy => uploading;

  /// True when the entry carries something submit-worthy.
  /// EQUIPMENT is special: it's satisfied only when CAMERA is answered
  /// (a preset item OR CAMERA_OTHER with non-empty free text). LENS/DRONE/
  /// GIMBAL never block submit — DRONE/GIMBAL have explicit "নেই" options.
  bool get hasContent {
    if (code == _kDocEquipment) {
      final cam = equipment['CAMERA'];
      final single = cam?.single;
      if (single == null || single.isEmpty) return false;
      if (single.endsWith('_OTHER')) return cam!.other.trim().isNotEmpty;
      return true;
    }
    if (code == _kDocExperience) {
      return linkUrl.trim().isNotEmpty;
    }
    if (code == _kDocPortfolio) {
      return useLink ? linkUrl.trim().isNotEmpty : files.isNotEmpty;
    }
    return files.isNotEmpty;
  }

  /// Drives the ✓/upload icon + border colour on the card. BSC_DIPLOMA counts
  /// as satisfied when the student checkbox is on, even without a file.
  bool get isSatisfied {
    if (code == _kDocBscDiploma) return currentlyStudying || hasContent;
    return hasContent;
  }

  /// The effective "must be filled" rule used by _canSubmit. BSC_DIPLOMA is
  /// special-cased: the backend flags it isRequired:false for some services,
  /// but the product rule is "always required unless the student checkbox is
  /// ticked" — so we ignore isRequired for that code.
  bool get blocksSubmit {
    if (code == _kDocBscDiploma) return !currentlyStudying && !hasContent;
    return isRequired && !hasContent;
  }

  /// The flat list of documents this entry contributes at submit-time.
  /// - BSC_DIPLOMA + checkbox on → contributes nothing
  /// - EXPERIENCE / EQUIPMENT / Portfolio-with-link → one doc, typed text as fileUrl
  /// - Everything else → one doc per uploaded file
  Iterable<_PendingDoc> docsForSubmit() sync* {
    if (code == _kDocBscDiploma && currentlyStudying) return;
    final isTextAsUrl = code == _kDocEquipment ||
        code == _kDocExperience ||
        (code == _kDocPortfolio && useLink);
    if (isTextAsUrl) {
      final trimmed = linkUrl.trim();
      if (trimmed.isEmpty) return;
      yield _PendingDoc(fileUrl: trimmed, originalFileName: null, mimeType: null);
      return;
    }
    for (final f in files) {
      yield _PendingDoc(fileUrl: f.fileUrl, originalFileName: f.fileName, mimeType: f.mimeType);
    }
  }
}

class _PendingDoc {
  final String fileUrl;
  final String? originalFileName;
  final String? mimeType;
  _PendingDoc({required this.fileUrl, this.originalFileName, this.mimeType});
}

Future<_UploadedFile> _uploadFile(XFile f) async {
  final bytes = await f.readAsBytes();
  final mime = _inferMime(f);
  final url = await OnboardingService.instance.uploadFile(
    fileBase64: base64Encode(bytes),
    fileName: f.name,
    mimeType: mime,
  );
  return _UploadedFile(fileUrl: url, fileName: f.name, mimeType: mime, previewBytes: bytes);
}

String _inferMime(XFile f) {
  final m = f.mimeType;
  if (m != null && m.isNotEmpty) return m;
  final ext = f.name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(color: AppColors.ivory)),
    backgroundColor: const Color(0xFFEF4444),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(16),
  ));
}
