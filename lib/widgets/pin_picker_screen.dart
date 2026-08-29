import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';

/// Manual location picker — tap the map to drop a pin, confirm to return the
/// LatLng. Used wherever live GPS failed (geocoder couldn't find an address,
/// or location services are off) and the previous fallback was asking the
/// user to type raw latitude/longitude numbers, which nobody actually knows.
class PinPickerScreen extends StatefulWidget {
  final bool isBn;
  final LatLng? initialPosition; // centers the map here instead of Dhaka, if known
  const PinPickerScreen({super.key, required this.isBn, this.initialPosition});

  @override
  State<PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends State<PinPickerScreen> {
  static const _dhaka = LatLng(23.8103, 90.4125);
  LatLng? _pin;

  @override
  void initState() {
    super.initState();
    _pin = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    final isBn = widget.isBn;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(isBn ? 'ম্যাপে পিন দিন' : 'Drop a pin',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: widget.initialPosition ?? _dhaka, zoom: 12),
          onTap: (p) => setState(() => _pin = p),
          markers: {
            if (_pin != null)
              Marker(markerId: const MarkerId('pin'), position: _pin!),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        Positioned(
          left: 16, right: 16, bottom: 24,
          child: GestureDetector(
            onTap: _pin == null ? null : () => Navigator.pop(context, _pin),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: _pin == null ? AppColors.textMuted : AppColors.deepBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: Text(
                  _pin == null
                      ? (isBn ? 'ম্যাপে ট্যাপ করে জায়গাটি দেখান' : 'Tap the map to mark the place')
                      : (isBn ? 'এই জায়গাটিই ঠিক আছে' : 'Confirm this location'),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
            ),
          ),
        ),
      ]),
    );
  }
}
