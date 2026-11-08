import 'package:flutter/material.dart';

import 'api.dart';

const stateNames = [
  'Alabama',
  'Alaska',
  'Arizona',
  'Arkansas',
  'California',
  'Colorado',
  'Connecticut',
  'Delaware',
  'Florida',
  'Georgia',
  'Hawaii',
  'Idaho',
  'Illinois',
  'Indiana',
  'Iowa',
  'Kansas',
  'Kentucky',
  'Louisiana',
  'Maine',
  'Maryland',
  'Massachusetts',
  'Michigan',
  'Minnesota',
  'Mississippi',
  'Missouri',
  'Montana',
  'Nebraska',
  'Nevada',
  'New Hampshire',
  'New Jersey',
  'New Mexico',
  'New York',
  'North Carolina',
  'North Dakota',
  'Ohio',
  'Oklahoma',
  'Oregon',
  'Pennsylvania',
  'Rhode Island',
  'South Carolina',
  'South Dakota',
  'Tennessee',
  'Texas',
  'Utah',
  'Vermont',
  'Virginia',
  'Washington',
  'West Virginia',
  'Wisconsin',
  'Wyoming',
];

class OfferPage extends StatefulWidget {
  const OfferPage({
    super.key,
    required this.kind,
    required this.username,
    required this.profile,
  });
  final String kind;
  final String username;
  final Map<String, dynamic> profile;
  @override
  State<OfferPage> createState() => _OfferPageState();
}

class _OfferPageState extends State<OfferPage> {
  final title = TextEditingController();
  final address = TextEditingController();
  final city = TextEditingController();
  final zip = TextEditingController();
  final details = TextEditingController();
  final age = TextEditingController();
  String? category;
  String? state;
  DateTime? from;
  DateTime? to;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final address = widget.profile['address'];
    final merchantState = address is Map ? address['state'] : null;
    state = stateNames.contains(merchantState)
        ? merchantState as String
        : stateNames.first;
  }

  @override
  void dispose() {
    for (final controller in [title, address, city, zip, details, age]) {
      controller.dispose();
    }
    super.dispose();
  }

  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> chooseDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          from = picked;
        } else {
          to = picked;
        }
      });
    }
  }

  Future<void> save() async {
    if ([
          title,
          address,
          city,
          zip,
          details,
        ].any((c) => c.text.trim().isEmpty) ||
        from == null ||
        to == null ||
        state == null) {
      setState(
        () => error = 'Complete the title, dates, address, city, ZIP, state, and details.',
      );
      return;
    }
    if (to!.isBefore(from!)) {
      setState(() => error = 'End date must not be before start date.');
      return;
    }
    if (age.text.isNotEmpty &&
        (int.tryParse(age.text) == null || int.parse(age.text) < 0)) {
      setState(() => error = 'Enter a valid age limit.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final isDeal = widget.kind == 'Deal';
    final payload = <String, dynamic>{
      'merchantId': widget.username,
      'merchantName': widget.username,
      'title': title.text.trim(),
      if (isDeal) 'category': category ?? '' else 'type': category ?? '',
      'from': date(from!),
      'to': date(to!),
      'address': address.text.trim(),
      'city': city.text.trim(),
      'pin': zip.text.trim(),
      'state': state,
      'details': details.text.trim(),
      'ageLimit': age.text.trim(),
    };
    try {
      await ArrivioApi().request(
        isDeal ? ArrivioApi.saveDeal : ArrivioApi.saveCoupon,
        body: payload,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'Unable to save ${widget.kind.toLowerCase()}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.kind == 'Deal'
        ? ['Dining', 'Retail', 'Fitness', 'Wellness', 'Travel']
        : ['Percent off', 'Flat discount', 'Free shipping', 'Buy one get one'];
    return Scaffold(
      appBar: AppBar(title: Text('Add ${widget.kind}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final field in [
            (title, '${widget.kind} title'),
            (address, 'Applicable address'),
            (city, 'City'),
            (zip, 'PIN / ZIP code'),
            (details, '${widget.kind} details'),
            (age, 'Age limit'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: field.$1,
                keyboardType: field.$1 == age
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: field.$2,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: InputDecoration(
              labelText: widget.kind == 'Deal' ? 'Category' : 'Coupon type',
            ),
            items: categories
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => category = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: state,
            decoration: const InputDecoration(labelText: 'State'),
            items: stateNames
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => state = v),
          ),
          TextButton(
            onPressed: () => chooseDate(true),
            child: Text('From: ${from == null ? 'Select date' : date(from!)}'),
          ),
          TextButton(
            onPressed: () => chooseDate(false),
            child: Text('To: ${to == null ? 'Select date' : date(to!)}'),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: loading ? null : save,
            child: Text(loading ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}
