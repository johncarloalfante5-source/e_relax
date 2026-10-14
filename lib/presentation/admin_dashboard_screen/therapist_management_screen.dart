import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/service_catalog.dart';
import '../../data/therapist_roster_store.dart';
import '../../theme/app_theme.dart';

class TherapistManagementScreen extends StatefulWidget {
  const TherapistManagementScreen({super.key});

  @override
  State<TherapistManagementScreen> createState() =>
      _TherapistManagementScreenState();
}

class _TherapistManagementScreenState extends State<TherapistManagementScreen> {
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  Set<String> _selectedTherapistIds = {};

  @override
  void initState() {
    super.initState();
    TherapistRosterStore.instance.watchDutyForDate(_selectedDate);
    _selectedTherapistIds = TherapistRosterStore.instance
        .onDutyForDate(_selectedDate)
        .map((therapist) => therapist.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.backgroundLight,
    appBar: AppBar(
      title: const Text('Therapist Management'),
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          tooltip: 'Add therapist',
          onPressed: () => _editTherapist(context),
          icon: const Icon(Icons.person_add_alt_1_rounded),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: TherapistRosterStore.instance,
      builder: (context, _) {
        final roster = TherapistRosterStore.instance.therapists;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Text(
              'Daily duty roster',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose the therapists working on a date. Only selected, unbooked therapists will be offered for online appointments.',
              style: TextStyle(color: AppTheme.onSurfaceVariantLight),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.black12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _chooseDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(_formatDate(_selectedDate)),
                    ),
                    const SizedBox(height: 10),
                    if (roster.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Add a therapist to create a duty roster.'),
                      )
                    else
                      for (final therapist in roster)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selectedTherapistIds.contains(therapist.id),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedTherapistIds.add(therapist.id);
                              } else {
                                _selectedTherapistIds.remove(therapist.id);
                              }
                            });
                          },
                          title: Text(therapist.name),
                          subtitle: Text(therapist.specialty),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppTheme.primary,
                        ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: roster.isEmpty ? null : _saveDuty,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save duty roster'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${TherapistRosterStore.instance.onDutyForDate(_selectedDate).length} therapist(s) currently saved for this date',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSurfaceVariantLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Therapists',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _editTherapist(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add therapist'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (roster.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No therapists yet. Add the first therapist.'),
                ),
              )
            else
              for (final therapist in roster)
                Card(
                  color: Colors.white,
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryContainer,
                      backgroundImage: therapist.profileImageBytes == null
                          ? (TherapistRosterStore.instance.photoUrl(therapist) == null
                              ? null
                              : NetworkImage(TherapistRosterStore.instance.photoUrl(therapist)!))
                          : MemoryImage(therapist.profileImageBytes!) as ImageProvider,
                      child: therapist.profileImageBytes == null && TherapistRosterStore.instance.photoUrl(therapist) == null
                          ? Text(
                              therapist.name.isEmpty
                                  ? '?'
                                  : therapist.name[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      therapist.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${therapist.specialty}\n${therapist.email}\n${therapist.phone.isEmpty ? 'No phone provided' : therapist.phone}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Edit therapist',
                      onPressed: () => _editTherapist(context, therapist),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                ),
          ],
        );
      },
    ),
  );

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    setState(() => _selectedDate = DateUtils.dateOnly(date));
    await TherapistRosterStore.instance.watchDutyForDate(_selectedDate);
    if (mounted) setState(() => _selectedTherapistIds = TherapistRosterStore.instance
        .onDutyForDate(_selectedDate).map((therapist) => therapist.id).toSet());
  }

  Future<void> _saveDuty() async {
    try {
      await TherapistRosterStore.instance.setDutyForDate(_selectedDate, _selectedTherapistIds);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Duty roster saved for ${_formatDate(_selectedDate)}')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save duty roster: $error')),
      );
    }
  }

  Future<void> _editTherapist(
    BuildContext context, [
    TherapistProfile? therapist,
  ]) async {
    final name = TextEditingController(text: therapist?.name ?? '');
    final email = TextEditingController(text: therapist?.email ?? '');
    final phone = TextEditingController(text: therapist?.phone ?? '');
    Uint8List? profileImageBytes = therapist?.profileImageBytes;
    final specialties = ServiceCatalog.services
        .map((service) => service['name'] as String)
        .toSet()
        .toList();
    var selectedSpecialty = specialties.contains(therapist?.specialty)
        ? therapist!.specialty
        : specialties.first;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<
      (String, String, String, String, Uint8List?)
    >(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(therapist == null ? 'Add therapist' : 'Edit therapist'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _textField(name, 'Full name'),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Profile photo (optional)',
                        style: Theme.of(dialogContext).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: AppTheme.primaryContainer,
                          backgroundImage: profileImageBytes == null
                              ? null
                              : MemoryImage(profileImageBytes!),
                          child: profileImageBytes == null
                              ? const Icon(
                                  Icons.person_outline_rounded,
                                  color: AppTheme.primary,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final files = await FilePicker.pickFiles(
                                  type: FileType.image,
                                );
                                if (files.isEmpty) return;
                                final bytes = await files.first.readAsBytes();
                                if (!dialogContext.mounted) return;
                                setDialogState(() => profileImageBytes = bytes);
                              } catch (_) {
                                if (!dialogContext.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not load that image.'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text(
                              profileImageBytes == null
                                  ? 'Add profile photo'
                                  : 'Change profile photo',
                            ),
                          ),
                        ),
                        if (profileImageBytes != null)
                          IconButton(
                            tooltip: 'Remove profile photo',
                            onPressed: () =>
                                setDialogState(() => profileImageBytes = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedSpecialty,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Massage service specialty',
                        border: OutlineInputBorder(),
                      ),
                      items: specialties
                          .map(
                            (serviceName) => DropdownMenuItem(
                              value: serviceName,
                              child: Text(serviceName),
                            ),
                          )
                          .toList(),
                      validator: (value) => value == null
                          ? 'Select a massage service specialty'
                          : null,
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedSpecialty = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      email,
                      'Login email (optional)',
                      isRequired: false,
                      keyboard: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      phone,
                      'Contact number (optional)',
                      isRequired: false,
                      keyboard: TextInputType.phone,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(dialogContext, (
                  name.text.trim(),
                  selectedSpecialty,
                  email.text.trim(),
                  phone.text.trim(),
                  profileImageBytes,
                ));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    email.dispose();
    phone.dispose();
    if (result == null) return;
    try {
      if (therapist == null) {
      await TherapistRosterStore.instance.addTherapist(
        name: result.$1,
        specialty: result.$2,
        email: result.$3,
        phone: result.$4,
        profileImageBytes: result.$5,
      );
      } else {
      await TherapistRosterStore.instance.updateTherapist(
        therapist.id,
        name: result.$1,
        specialty: result.$2,
        email: result.$3,
        phone: result.$4,
        profileImageBytes: result.$5,
      );
      }
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save therapist: $error')),
      );
    }
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool isRequired = true,
    TextInputType keyboard = TextInputType.text,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) => isRequired && (value == null || value.trim().isEmpty)
        ? 'Enter $label'
        : null,
  );

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
