import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../services/premium_service.dart';
import '../../l10n/app_localizations.dart';

// Идентификатор продукта — должен совпадать с тем, что настроен в
// Google Play Console (subscriptions) и App Store Connect (auto-renewable)
const _kMonthlyId = 'aura_scanner_premium_monthly';
const _kYearlyId = 'aura_scanner_premium_yearly';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _sub;

  bool _storeAvailable = false;
  bool _loading = true;
  bool _purchasing = false;
  bool _isPremium = false;
  DateTime? _expiresAt;

  List<ProductDetails> _products = [];
  String? _selectedId = _kMonthlyId;

  @override
  void initState() {
    super.initState();
    _isPremium = PremiumService().isPremium;
    _expiresAt = PremiumService().expiresAt;
    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate, onError: _onPurchaseError);
    _init();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final available = await _iap.isAvailable();
    if (!available) {
      if (mounted) setState(() { _storeAvailable = false; _loading = false; });
      return;
    }
    final response = await _iap.queryProductDetails({_kMonthlyId, _kYearlyId});
    if (mounted) {
      setState(() {
        _storeAvailable = true;
        _loading = false;
        _products = response.productDetails
          ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
      });
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasing = true);
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        // Сначала верифицируем receipt на сервере. Локальный флаг
        // ставим только после подтверждения — иначе клиент может
        // активировать Premium без реальной покупки.
        final platform = Platform.isIOS ? 'ios' : 'android';
        final receipt = purchase.verificationData.serverVerificationData;

        bool serverVerified = false;
        String? serverError;
        try {
          await PremiumService().activateOnServer(
            platform: platform,
            productId: purchase.productID,
            receipt: receipt,
          );
          serverVerified = true;
          await PremiumService().activate();
          await PremiumService().syncWithServer();
        } catch (e) {
          serverError = e.toString().replaceFirst('Exception: ', '');
        }

        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        if (mounted) {
          setState(() {
            _purchasing = false;
            if (serverVerified) {
              _isPremium = true;
              _expiresAt = PremiumService().expiresAt;
            }
          });
          if (serverVerified) {
            _showSuccess();
          } else {
            final l10n = AppLocalizations.of(context);
            _showError(l10n.premiumPurchaseVerifyFailed(serverError ?? l10n.premiumServerError));
          }
        }
      } else if (purchase.status == PurchaseStatus.error) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        if (mounted) {
          setState(() => _purchasing = false);
          _showError(purchase.error?.message ?? AppLocalizations.of(context).premiumPaymentError);
        }
      } else if (purchase.status == PurchaseStatus.canceled) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        if (mounted) setState(() => _purchasing = false);
      }
    }
  }

  void _onPurchaseError(dynamic error) {
    if (mounted) {
      setState(() => _purchasing = false);
      _showError(error.toString());
    }
  }

  Future<void> _buy() async {
    if (_selectedId == null || _products.isEmpty) return;
    final product = _products.firstWhere(
      (p) => p.id == _selectedId,
      orElse: () => _products.first,
    );
    setState(() => _purchasing = true);
    final param = PurchaseParam(productDetails: product);
    try {
      if (Platform.isIOS) {
        await _iap.buyNonConsumable(purchaseParam: param);
      } else {
        await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        _showError(e.toString());
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _purchasing = true);
    try {
      await _iap.restorePurchases();
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        _showError('${AppLocalizations.of(context).premiumRestoreFailed}: $e');
      }
    }
  }

  void _showSuccess() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: Colors.green, size: 40),
              ),
              const SizedBox(height: 16),
              Text(l10n.premiumActivatedTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 8),
              Text(l10n.premiumUnlockedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.grey.shade600)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(l10n.premiumGreat),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EDF5);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white38 : Colors.grey.shade500;
    final dividerColor = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Premium',
            style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2CA5E0)))
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Шапка
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1976D2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                    child: Column(
                      children: [
                        Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade500,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.45),
                                blurRadius: 24, spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.workspace_premium, size: 40, color: Colors.white),
                        ),
                        const SizedBox(height: 18),
                        Text(l10n.premiumBrandTitle,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(l10n.premiumHeadline,
                            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.75))),
                        if (_isPremium) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                                const SizedBox(width: 6),
                                Text(l10n.premiumActive, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (!_isPremium) ...[
                    // Выбор плана
                    Transform.translate(
                      offset: const Offset(0, -22),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: cardBorder),
                            boxShadow: isDark ? null : [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 4)),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              if (_storeAvailable && _products.isNotEmpty) ...[
                                ..._products.map((p) => _buildPlanTile(p, isDark, textColor, subColor, cardBorder)),
                                const SizedBox(height: 16),
                              ] else if (!_storeAvailable) ...[
                                Icon(Icons.store_mall_directory_outlined, size: 40, color: subColor),
                                const SizedBox(height: 8),
                                Text(l10n.premiumStoreUnavailable, style: TextStyle(color: subColor)),
                                const SizedBox(height: 16),
                              ] else ...[
                                // Продукты не загружены — показываем fallback с ценами
                                _buildFallbackPlan(isDark, textColor, subColor, cardBorder),
                                const SizedBox(height: 16),
                              ],
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  onPressed: (_purchasing || !_storeAvailable) ? null : _buy,
                                  child: _purchasing
                                      ? const SizedBox(
                                          width: 20, height: 20,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : Text(l10n.premiumSubscribe,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(l10n.premiumCancelAnytime,
                                  style: TextStyle(fontSize: 12, color: subColor)),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: _purchasing ? null : _restore,
                                child: Text(l10n.premiumRestore,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF2CA5E0))),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Transform.translate(
                      offset: const Offset(0, -22),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildActiveSubscriptionCard(
                          isDark, textColor, subColor, cardBg, cardBorder,
                        ),
                      ),
                    ),
                  ],

                  // Список возможностей
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(l10n.premiumWhatsIncluded,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: subColor, letterSpacing: 0.8)),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
                            boxShadow: isDark ? null : [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            children: [
                              _FeatureTile(icon: Icons.library_books, iconColor: Colors.purple,
                                  title: l10n.premiumFeat10PagesTitle, subtitle: l10n.premiumFeat10PagesSub,
                                  textColor: textColor, subColor: subColor, dividerColor: dividerColor),
                              _FeatureTile(icon: Icons.auto_fix_high_outlined, iconColor: Colors.orange,
                                  title: l10n.premiumFeatRestoreTitle, subtitle: l10n.premiumFeatRestoreSub,
                                  textColor: textColor, subColor: subColor, dividerColor: dividerColor),
                              _FeatureTile(icon: Icons.highlight, iconColor: Colors.yellow.shade700,
                                  title: l10n.premiumFeatHighlightTitle, subtitle: l10n.premiumFeatHighlightSub,
                                  textColor: textColor, subColor: subColor, dividerColor: dividerColor),
                              _FeatureTile(icon: Icons.lock_outline, iconColor: Colors.blue,
                                  title: l10n.premiumFeatPasswordTitle, subtitle: l10n.premiumFeatPasswordSub,
                                  textColor: textColor, subColor: subColor, dividerColor: dividerColor),
                              _FeatureTile(icon: Icons.voice_chat, iconColor: Colors.teal,
                                  title: l10n.premiumFeatVoiceTitle, subtitle: l10n.premiumFeatVoiceSub,
                                  textColor: textColor, subColor: subColor, dividerColor: dividerColor),
                              _FeatureTile(icon: Icons.eco, iconColor: Colors.green,
                                  title: l10n.premiumFeatEcoTitle, subtitle: l10n.premiumFeatEcoSub,
                                  textColor: textColor, subColor: subColor, dividerColor: dividerColor, isLast: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            l10n.premiumStoreNote(Platform.isIOS ? 'App Store' : 'Google Play'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: subColor, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveSubscriptionCard(
    bool isDark,
    Color textColor,
    Color subColor,
    Color cardBg,
    Color cardBorder,
  ) {
    final l10n = AppLocalizations.of(context);
    final expires = _expiresAt;
    final expiresText = expires != null
        ? '${expires.day.toString().padLeft(2, '0')}.'
            '${expires.month.toString().padLeft(2, '0')}.'
            '${expires.year}'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified, color: Colors.green, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.premiumSubscriptionActive,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textColor)),
                    const SizedBox(height: 2),
                    Text(
                      expiresText != null ? l10n.premiumValidUntil(expiresText) : l10n.premiumAccessOpen,
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _purchasing ? null : _openManageSubscription,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(Platform.isIOS ? l10n.premiumManageAppStore : l10n.premiumManageGooglePlay),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2CA5E0),
                side: const BorderSide(color: Color(0xFF2CA5E0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: TextButton.icon(
              onPressed: _purchasing ? null : _restore,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.premiumRestore),
              style: TextButton.styleFrom(
                foregroundColor: subColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openManageSubscription() async {
    final l10n = AppLocalizations.of(context);
    final ok = await PremiumService().openManageSubscription();
    if (!ok && mounted) {
      _showError(l10n.premiumManageOpenFailed);
    }
  }

  Widget _buildPlanTile(
    ProductDetails product,
    bool isDark,
    Color textColor,
    Color subColor,
    Color borderColor,
  ) {
    final l10n = AppLocalizations.of(context);
    final isSelected = _selectedId == product.id;
    final isYearly = product.id == _kYearlyId;
    return GestureDetector(
      onTap: () => setState(() => _selectedId = product.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2CA5E0).withValues(alpha: isDark ? 0.18 : 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF2CA5E0) : borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF2CA5E0) : subColor,
                  width: 2,
                ),
                color: isSelected ? const Color(0xFF2CA5E0) : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 12)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(isYearly ? l10n.premiumPlanYearly : l10n.premiumPlanMonthly,
                          style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 14)),
                      if (isYearly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(l10n.premiumBestValue, style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(product.description,
                      style: TextStyle(fontSize: 11, color: subColor)),
                ],
              ),
            ),
            Text(product.price,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackPlan(bool isDark, Color textColor, Color subColor, Color borderColor) {
    final l10n = AppLocalizations.of(context);
    final plans = [
      {'id': _kMonthlyId, 'title': l10n.premiumPlanMonthly, 'price': '299 ₽/мес', 'yearly': false},
      {'id': _kYearlyId, 'title': l10n.premiumPlanYearly, 'price': '1 990 ₽/год', 'yearly': true},
    ];
    return Column(
      children: plans.map((plan) {
        final id = plan['id'] as String;
        final isSelected = _selectedId == id;
        final isYearly = plan['yearly'] as bool;
        return GestureDetector(
          onTap: () => setState(() => _selectedId = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF2CA5E0).withValues(alpha: isDark ? 0.18 : 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFF2CA5E0) : borderColor,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? const Color(0xFF2CA5E0) : subColor, width: 2),
                    color: isSelected ? const Color(0xFF2CA5E0) : Colors.transparent,
                  ),
                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 12) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Text(plan['title'] as String,
                          style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 14)),
                      if (isYearly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(l10n.premiumBestValue, style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(plan['price'] as String,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textColor)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subColor;
  final Color dividerColor;
  final bool isLast;

  const _FeatureTile({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.textColor, required this.subColor,
    required this.dividerColor, this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: subColor)),
                  ],
                ),
              ),
              Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, indent: 70, color: dividerColor),
      ],
    );
  }
}
