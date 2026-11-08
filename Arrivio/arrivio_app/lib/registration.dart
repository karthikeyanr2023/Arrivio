import 'package:flutter/material.dart';

import 'api.dart';

const countries = [
  'United States',
  'Canada',
  'United Kingdom',
  'Australia',
  'India',
  'Germany',
  'France',
  'Japan',
  'Singapore',
];
const states = [
  'AL',
  'AK',
  'AZ',
  'AR',
  'CA',
  'CO',
  'CT',
  'DE',
  'FL',
  'GA',
  'HI',
  'ID',
  'IL',
  'IN',
  'IA',
  'KS',
  'KY',
  'LA',
  'ME',
  'MD',
  'MA',
  'MI',
  'MN',
  'MS',
  'MO',
  'MT',
  'NE',
  'NV',
  'NH',
  'NJ',
  'NM',
  'NY',
  'NC',
  'ND',
  'OH',
  'OK',
  'OR',
  'PA',
  'RI',
  'SC',
  'SD',
  'TN',
  'TX',
  'UT',
  'VT',
  'VA',
  'WA',
  'WV',
  'WI',
  'WY',
];
const preferences = {
  'Food': ['Asian', 'Italian', 'Street Food', 'Desserts', 'Coffee Shops'],
  'Events': [
    'Music Festivals',
    'Dance',
    'Farmers Market',
    'Art Fairs',
    'Theater',
  ],
  'Sports': [
    'Cycling',
    'Hiking',
    'Running',
    'Yoga Retreats',
    'Beach Volleyball',
  ],
  'Deals': [
    'Starbucks Deals',
    'Flower Shop Deals',
    'Whole Foods Deals',
    'Costco Deals',
    'Local Boutique Deals',
    'Parking Deals',
  ],
};

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final street = TextEditingController();
  final city = TextEditingController();
  final zip = TextEditingController();
  final selected = <String>{};
  String? country;
  String? state;
  String? error;
  bool loading = false;
  final api = ArrivioApi();

  @override
  void dispose() {
    for (final controller in [name, email, street, city, zip]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (name.text.trim().isEmpty ||
        !email.text.trim().endsWith('@gmail.com') ||
        country == null ||
        street.text.trim().isEmpty ||
        city.text.trim().isEmpty ||
        zip.text.trim().isEmpty ||
        (country == 'United States' && state == null) ||
        selected.isEmpty) {
      setState(
        () => error = 'Complete all fields, use a Gmail address, and select at least one preference.',
      );
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final addressText = [
        street.text.trim(),
        city.text.trim(),
        state ?? '',
        zip.text.trim(),
        country!,
      ].where((s) => s.isNotEmpty).join(', ');
      final dynamic result = await api.request(
        ArrivioApi.geocode,
        body: {'addressText': addressText},
      );
      if (result is! Map) {
        throw const FormatException('Invalid geocode response');
      }
      final dynamic geometry = result['geometry'];
      final dynamic location = geometry is Map ? geometry['location'] : null;
      final lat = result['lat'] ?? (location is Map ? location['lat'] : null);
      final lng = result['lng'] ?? (location is Map ? location['lng'] : null);
      if (lat == null || lng == null) {
        throw const FormatException('Geocode returned no coordinates');
      }
      final geo = {
        'lat': lat,
        'lng': lng,
        'source': result['source'] ?? 'geocode_api',
      };
      final profile = <String, dynamic>{
        'fullName': name.text.trim(),
        'email': email.text.trim(),
        'country': country,
        'address': {
          'street': street.text.trim(),
          'city': city.text.trim(),
          'state': state ?? '',
          'zipcode': zip.text.trim(),
          'geocode': geo,
        },
        'geocode': geo,
        'preferences': selected.toList(),
      };
      await api.request(ArrivioApi.signup, body: profile);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReviewProfilePage(profile: profile),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = 'Unable to create profile: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create your Arrivio profile')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Password is disabled for this prototype.'),
        for (final field in [
          (name, 'Name'),
          (email, 'User Name (Gmail only)'),
          (street, 'Street address'),
          (city, 'City'),
          (zip, 'Zip code'),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: field.$1,
              decoration: InputDecoration(
                labelText: field.$2,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: country,
          decoration: const InputDecoration(labelText: 'Country'),
          items: countries
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() {
            country = v;
            state = null;
          }),
        ),
        if (country == 'United States')
          DropdownButtonFormField<String>(
            initialValue: state,
            decoration: const InputDecoration(labelText: 'State'),
            items: states
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => state = v),
          ),
        const SizedBox(height: 20),
        Text('Preferences', style: Theme.of(context).textTheme.titleLarge),
        for (final group in preferences.entries)
          ExpansionTile(
            title: Text(group.key),
            children: [
              for (final item in group.value)
                CheckboxListTile(
                  title: Text(item),
                  value: selected.contains('${group.key}:$item'),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      selected.add('${group.key}:$item');
                    } else {
                      selected.remove('${group.key}:$item');
                    }
                  }),
                ),
            ],
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: loading ? null : submit,
          child: Text(loading ? 'Saving...' : 'Create Account'),
        ),
      ],
    ),
  );
}

class ReviewProfilePage extends StatelessWidget {
  const ReviewProfilePage({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context) {
    final address = profile['address'] as Map;
    final geocode = profile['geocode'] as Map;
    return Scaffold(
      appBar: AppBar(title: const Text('Review your profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final row in <String, Object?>{
            'Name': profile['fullName'],
            'Email': profile['email'],
            'Country': profile['country'],
            'Street': address['street'],
            'City': address['city'],
            'State': address['state'],
            'Zip': address['zipcode'],
            'Latitude': geocode['lat'],
            'Longitude': geocode['lng'],
            'Preferences': (profile['preferences'] as List).join(', '),
          }.entries)
            ListTile(
              title: Text(row.key),
              subtitle: Text('${row.value ?? ''}'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Confirm profile'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Edit profile'),
          ),
        ],
      ),
    );
  }
}
