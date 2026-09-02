import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_colors.dart';
import '../services/api_service.dart';

/// Lets a patient request verification as Senior Citizen / PWD / Pregnant by
/// submitting a photo of their ID/certificate. Patients can no longer set
/// their own patientType directly (see AppState.updateCurrentUserProfile) —
/// this is the real channel: staff review the photo and approve/reject
/// (see the "Type Requests" tab on the staff tablet's Patient Inquiries
/// screen).
///
/// Requires the `image_picker` package — not previously a dependency of
/// this project. Add to pubspec.yaml:
///   image_picker: ^1.0.0
/// (or your existing version if already used elsewhere in the project).
class PatientTypeRequestScreen extends StatefulWidget {
  const PatientTypeRequestScreen({super.key});
  @override
  State<PatientTypeRequestScreen> createState() => _PatientTypeRequestScreenState();
}

class _PatientTypeRequestScreenState extends State<PatientTypeRequestScreen> {
  static const _types = ['Senior Citizen', 'PWD', 'Pregnant'];

  bool _loadingStatus = true;
  Map<String, dynamic>? _existingRequest;

  String? _selectedType;
  File? _photo;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final req = await ApiService.getMyPatientTypeRequest();
      if (!mounted) return;
      setState(() => _existingRequest = req);
    } catch (_) {
      // Non-fatal — the form below still works even if status couldn't load.
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _photo = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null) {
      setState(() => _error = 'Please select what you\'re requesting.');
      return;
    }
    if (_photo == null) {
      setState(() => _error = 'Please attach a photo of your ID or certificate.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await ApiService.submitPatientTypeRequest(
        requestedType: _selectedType!,
        photo: _photo!,
      );
      if (!mounted) return;
      await _loadStatus();
      setState(() { _selectedType = null; _photo = null; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF16A34A),
          content: Text('Request submitted — staff will review it shortly.'),
        ));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Request Account Update'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_existingRequest != null) _statusCard(_existingRequest!),
                if (_existingRequest == null || _existingRequest!['status'] != 'pending') ...[
                  const SizedBox(height: 16),
                  _form(),
                ],
              ]),
            ),
    );
  }

  Widget _statusCard(Map<String, dynamic> req) {
    final status = req['status']?.toString() ?? 'pending';
    final type = req['requestedType']?.toString() ?? '';
    final note = req['reviewNote']?.toString() ?? '';
    final color = status == 'approved'
        ? const Color(0xFF16A34A)
        : status == 'rejected'
            ? const Color(0xFFDC2626)
            : const Color(0xFFD97706);
    final label = status == 'approved'
        ? 'Approved'
        : status == 'rejected'
            ? 'Rejected'
            : 'Pending Review';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            status == 'approved'
                ? Icons.check_circle_rounded
                : status == 'rejected'
                    ? Icons.cancel_rounded
                    : Icons.hourglass_top_rounded,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Text('Requested: $type', style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
        if (status == 'rejected' && note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Staff note: $note', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ],
        if (status == 'pending') ...[
          const SizedBox(height: 6),
          const Text(
            'Your request is awaiting staff review. You\'ll be able to submit a new request once this one is resolved.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ]),
    );
  }

  Widget _form() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Submit a photo of your Senior Citizen ID, PWD ID, or pregnancy certificate — staff will review it and update your account.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
        ),
        const SizedBox(height: 16),
        const Text('Requesting', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _types.map((t) {
            final selected = _selectedType == t;
            return GestureDetector(
              onTap: () => setState(() => _selectedType = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade300),
                ),
                child: Text(t,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : Colors.black87)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        const Text('ID / Certificate Photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_photo!, height: 180, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Camera'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Gallery'),
            ),
          ),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
