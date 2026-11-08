import 'package:flutter/material.dart';

import 'api.dart';
import 'offer.dart';
import 'shared_destination.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.username,
    required this.profile,
    required this.isMerchant,
    this.api,
    this.shared,
  });
  final String username;
  final Map<String, dynamic> profile;
  final bool isMerchant;
  final ArrivioApi? api;
  final SharedDestination? shared;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final api = widget.api ?? ArrivioApi();
  final destination = TextEditingController();
  bool loading = false;
  String loadingMessage = 'Loading...';
  String? message;
  String? coordinates;
  List<Map<String, dynamic>>? nearby;
  List<Map<String, dynamic>> deals = [];
  List<Map<String, dynamic>> coupons = [];
  bool dealsLoaded = false;
  bool couponsLoaded = false;
  bool occasionPopupDisabled = false;
  int miles = 5;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    widget.shared?.addListener(_sharedDestinationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sharedDestinationChanged();
    });
    if (widget.isMerchant) loadOffers();
  }

  @override
  void dispose() {
    widget.shared?.removeListener(_sharedDestinationChanged);
    destination.dispose();
    super.dispose();
  }

  void _sharedDestinationChanged() {
    if (!mounted || loading) return;
    final shared = widget.shared;
    if (shared == null) return;
    if (shared.error != null) {
      setState(() => message = shared.error);
      return;
    }
    if (shared.destination == null) return;
    if (widget.isMerchant) {
      setState(
        () => message = 'Destination received. Log in as a user to use it.',
      );
      return;
    }
    final link = shared.takeDestination()!;
    setState(() {
      destination.text = link;
      tab = 0;
      coordinates = null;
      nearby = null;
      message = 'Shared destination added. Select Set destination to continue.';
    });
  }

  Future<void> loadOffers() async {
    setState(() {
      loading = true;
      loadingMessage = 'Loading published deals and coupons...';
      message = null;
    });
    final query = Uri(queryParameters: {'merchantId': widget.username}).query;
    final errors = <String>[];
    try {
      deals = await api.list('${ArrivioApi.merchantDeals}?$query');
      dealsLoaded = true;
    } catch (e) {
      dealsLoaded = false;
      errors.add('Deals: $e');
    }
    try {
      coupons = await api.list('${ArrivioApi.merchantCoupons}?$query');
      couponsLoaded = true;
    } catch (e) {
      couponsLoaded = false;
      errors.add('Coupons: $e');
    }
    if (mounted) {
      setState(() {
        message = errors.isEmpty
            ? null
            : 'Unable to load some offers: ${errors.join('; ')}';
        loading = false;
      });
      _sharedDestinationChanged();
    }
  }

  Future<void> findNearby() async {
    final text = destination.text.trim();
    if (text.isEmpty) {
      setState(() => message = 'Please enter a destination.');
      return;
    }
    setState(() {
      loading = true;
      loadingMessage = 'Resolving destination...';
      message = null;
      nearby = null;
      coordinates = null;
    });
    try {
      final dynamic result = await api.request(
        ArrivioApi.geocode,
        body: {'address': text, 'addressText': text},
      );
      if (result is! Map) {
        throw const FormatException('Invalid geocode response');
      }
      final dynamic inner = result['result'];
      final dynamic geometry = result['geometry'];
      final dynamic location = geometry is Map ? geometry['location'] : null;
      final lat =
          result['lat'] ??
          (inner is Map ? inner['lat'] : null) ??
          (location is Map ? location['lat'] : null);
      final lng =
          result['lng'] ??
          (inner is Map ? inner['lng'] : null) ??
          (location is Map ? location['lng'] : null);
      if (lat == null || lng == null) {
        throw const FormatException('Geocode returned no coordinates');
      }
      final latitude = num.parse('$lat');
      final longitude = num.parse('$lng');
      if (!mounted) return;
      final occasion = await askOccasion();
      if (!mounted) return;
      setState(() => loadingMessage = 'Retrieving deals and coupons...');
      final dynamic distance = await api.request(
        ArrivioApi.distance,
        body: {
          'lat': latitude,
          'lng': longitude,
          'userId': widget.username,
          'occasion': occasion,
        },
      );
      final dynamic data = distance is Map ? distance['data'] : distance;
      if (data is! List) {
        throw const FormatException('Unexpected distance response');
      }
      if (mounted) {
        setState(() {
          coordinates =
              'Lat: ${latitude.toStringAsFixed(6)}, Lng: ${longitude.toStringAsFixed(6)}';
          nearby = data
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (occasion.isNotEmpty && data.isNotEmpty) {
            final debug = distance is Map ? distance['rankingDebug'] : null;
            final ranking = debug is Map ? debug['occasionRanking'] : null;
            final status = ranking is Map ? '${ranking['status'] ?? ''}' : '';
            if (ranking == null ||
                RegExp(
                  'skipped|failed|unavailable',
                  caseSensitive: false,
                ).hasMatch(status)) {
              message = 'Nearby merchants loaded, but occasion ranking could not be confirmed.';
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = 'Unable to find nearby merchants: $e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        _sharedDestinationChanged();
      }
    }
  }

  Future<String> askOccasion() async {
    if (occasionPopupDisabled) return '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("What's the occasion?"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pick the one that fits this trip, or skip to see your results.',
              ),
              for (final occasion in [
                'Family',
                'Work',
                'Business',
                'Friends Hangout',
                'Party Night',
                'Chill & Chat',
                'Family Journey',
                'Festivities',
              ])
                TextButton(
                  onPressed: () => Navigator.pop(context, occasion),
                  child: Text(occasion),
                ),
              TextButton(
                onPressed: () {
                  occasionPopupDisabled = true;
                  Navigator.pop(context, '');
                },
                child: const Text("Don't show this again"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? '';
  }

  double distanceInMiles(Map<String, dynamic> item) {
    final direct = double.tryParse(
      '${item['distanceMiles'] ?? item['distance_miles'] ?? ''}',
    );
    if (direct != null && direct >= 0) return direct;
    final km = double.tryParse(
      '${item['distanceKm'] ?? item['distance_km'] ?? ''}',
    );
    return km == null || km < 0 ? double.infinity : km * 0.621371;
  }

  bool isActive(Map<String, dynamic> offer) {
    final value =
        offer['to'] ??
        offer['validTo'] ??
        offer['endDate'] ??
        offer['dateTo'] ??
        offer['expirationDate'] ??
        offer['expiry'] ??
        offer['valid_until'];
    if (value == null || '$value'.isEmpty) return true;
    final date = DateTime.tryParse('$value');
    if (date == null) return true;
    final end = '$value'.contains('T')
        ? date
        : date.add(const Duration(days: 1));
    return end.isAfter(DateTime.now());
  }

  List<Map<String, dynamic>> activeOffers(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(isActive)
        .toList();
  }

  void showOfferDetails(
    String merchantName,
    String kind,
    List<Map<String, dynamic>> offers,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.7,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                '$kind - $merchantName',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final offer in offers) ...[
                const Divider(),
                Text(
                  '${offer['title'] ?? offer['name'] ?? kind}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${offer['details'] ?? offer['description'] ?? 'Details not provided'}',
                ),
                if (offer['category'] != null || offer['type'] != null)
                  Text('Type: ${offer['category'] ?? offer['type']}'),
                if (offer['from'] != null ||
                    offer['validFrom'] != null ||
                    offer['startDate'] != null ||
                    offer['dateFrom'] != null ||
                    offer['to'] != null ||
                    offer['validTo'] != null ||
                    offer['endDate'] != null ||
                    offer['dateTo'] != null ||
                    offer['expirationDate'] != null ||
                    offer['expiry'] != null ||
                    offer['valid_until'] != null)
                  Text(
                    'Valid: ${offer['from'] ?? offer['validFrom'] ?? offer['startDate'] ?? offer['dateFrom'] ?? 'Not specified'} to ${offer['to'] ?? offer['validTo'] ?? offer['endDate'] ?? offer['dateTo'] ?? offer['expirationDate'] ?? offer['expiry'] ?? offer['valid_until'] ?? 'Not specified'}',
                  ),
                if ([
                  offer['address'],
                  offer['city'],
                  offer['state'],
                  offer['pin'],
                ].any((value) => value is String && value.trim().isNotEmpty))
                  Text(
                    'Location: ${[offer['address'], offer['city'], offer['state'], offer['pin']].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ')}',
                  ),
                if (offer['ageLimit'] != null &&
                    '${offer['ageLimit']}'.trim().isNotEmpty)
                  Text('Age limit: ${offer['ageLimit']}'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Welcome, ${widget.username}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Logout'),
        ),
      ],
    ),
    body: loading
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(loadingMessage, textAlign: TextAlign.center),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (tab == 1)
                ...profileDetails()
              else if (widget.isMerchant)
                ...merchantContent()
              else
                ...userContent(),
            ],
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) => setState(() => tab = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Welcome'),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    ),
  );

  List<Widget> profileDetails() {
    final address = widget.profile['address'] is Map
        ? widget.profile['address'] as Map
        : {};
    final business = widget.profile['businessDetails'] is Map
        ? widget.profile['businessDetails'] as Map
        : {};
    final geo = widget.profile['geocode'] is Map
        ? widget.profile['geocode'] as Map
        : address['geocode'] is Map
        ? address['geocode'] as Map
        : {};
    return [
      Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
      for (final entry in <String, Object?>{
        'Name': widget.profile['fullName'],
        'Email': widget.profile['email'],
        if (widget.isMerchant)
          'Phone':
              widget.profile['phone'] ??
              widget.profile['mobileNumber'] ??
              widget.profile['contactNumber'] ??
              business['phone'] ??
              business['contactNumber'],
        'Country': widget.profile['country'],
        'Street': address['street'],
        'City': address['city'],
        'State': address['state'],
        'Zip': address['zipcode'],
        if (widget.isMerchant) 'Business type': business['type'],
        if (widget.isMerchant) 'Business': business['title'],
        if (widget.isMerchant) 'Business option': business['option'],
        if (widget.isMerchant) 'License': business['licenseNumber'],
        if (widget.isMerchant) 'Tax ID': business['taxIdNumber'],
        if (widget.isMerchant)
          'Business info': business['businessInformation'] ?? business['notes'],
        if (widget.isMerchant)
          'Points of interest': (business['pois'] is List
              ? (business['pois'] as List).join(', ')
              : business['pois']),
        if (!widget.isMerchant)
          'Preferences': (widget.profile['preferences'] is List
              ? (widget.profile['preferences'] as List).join(', ')
              : ''),
        'Latitude': geo['lat'],
        'Longitude': geo['lng'],
      }.entries)
        ListTile(
          title: Text(entry.key),
          subtitle: Text('${entry.value ?? 'Not available'}'),
        ),
    ];
  }

  List<Widget> userContent() {
    final withinDistance = nearby
        ?.where((item) => distanceInMiles(item) <= miles)
        .toList();
    final results = withinDistance
        ?.where(
          (item) =>
              activeOffers(item['deals']).isNotEmpty ||
              activeOffers(item['coupons']).isNotEmpty,
        )
        .toList();
    final incompleteOffers =
        withinDistance?.any(
          (item) => item['deals'] is! List || item['coupons'] is! List,
        ) ??
        false;
    return [
      const Text('Enter a destination to find nearby merchants.'),
      const SizedBox(height: 12),
      TextField(
        controller: destination,
        decoration: const InputDecoration(
          labelText: 'Destination',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: findNearby, child: const Text('Set destination')),
      if (coordinates != null) Text(coordinates!),
      if (results != null) ...[
        const SizedBox(height: 16),
        const Text('Proximity'),
        Wrap(
          spacing: 8,
          children: [
            for (final value in [5, 10, 50, 100])
              ChoiceChip(
                label: Text('$value miles'),
                selected: miles == value,
                onSelected: (_) => setState(() => miles = value),
              ),
          ],
        ),
        if (miles >= 50)
          const Text(
            'The distance service may limit the search range, so results may be incomplete.',
          ),
        Text('Nearby merchants', style: Theme.of(context).textTheme.titleLarge),
        if (results.isEmpty && !incompleteOffers)
          Text(
            'No merchants with active deals or coupons were found within $miles miles.',
          ),
        if (incompleteOffers)
          const Text(
            'Offer information is unavailable for some nearby merchants, so results may be incomplete.',
          ),
        for (final item in results) merchantCard(item),
      ],
    ];
  }

  Widget merchantCard(Map<String, dynamic> item) {
    final business = item['businessDetails'] is Map
        ? item['businessDetails'] as Map
        : {};
    final address = item['address'] is Map
        ? item['address'] as Map
        : business['address'] is Map
        ? business['address'] as Map
        : {};
    final name =
        item['businessTitle'] ??
        item['business_title'] ??
        business['title'] ??
        business['businessTitle'] ??
        item['businessName'] ??
        item['business_name'] ??
        item['merchantName'] ??
        item['merchant_name'] ??
        item['name'] ??
        item['fullName'] ??
        item['username'] ??
        'Merchant';
    final phone =
        item['phone'] ??
        item['mobileNumber'] ??
        item['contactNumber'] ??
        business['phone'] ??
        business['contactNumber'] ??
        'Not available';
    final location = ['street', 'city', 'state', 'zipcode', 'country']
        .map((key) => address[key])
        .where((v) => v != null && '$v'.isNotEmpty)
        .join(', ');
    final deals = activeOffers(item['deals']);
    final coupons = activeOffers(item['coupons']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Phone: $phone\n${location.isEmpty ? 'Address unavailable' : location}\n${distanceInMiles(item).toStringAsFixed(2)} miles',
            ),
            Wrap(
              spacing: 8,
              children: [
                if (deals.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.local_offer_outlined, size: 18),
                    label: Text(
                      '${deals.length} ${deals.length == 1 ? 'Deal' : 'Deals'}',
                    ),
                    onPressed: () => showOfferDetails('$name', 'Deals', deals),
                  ),
                if (coupons.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(
                      Icons.confirmation_number_outlined,
                      size: 18,
                    ),
                    label: Text(
                      '${coupons.length} ${coupons.length == 1 ? 'Coupon' : 'Coupons'}',
                    ),
                    onPressed: () =>
                        showOfferDetails('$name', 'Coupons', coupons),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> merchantContent() => [
    Text('Merchant details', style: Theme.of(context).textTheme.titleLarge),
    ...profileDetails().skip(1),
    for (final group in [
      ('Published deals', deals, dealsLoaded),
      ('Published coupons', coupons, couponsLoaded),
    ]) ...[
      Text(group.$1, style: Theme.of(context).textTheme.titleLarge),
      if (!group.$3) const Text('Offers could not be loaded.'),
      if (group.$3 && !group.$2.any(isActive))
        const Text('No active offers published.'),
      for (final item
          in group.$3 ? group.$2.where(isActive) : <Map<String, dynamic>>[])
        Card(
          child: ListTile(
            title: Text('${item['title'] ?? 'Untitled offer'}'),
            subtitle: Text(
              '${item['category'] ?? item['type'] ?? 'General'}\n${item['address'] ?? ''}, ${item['city'] ?? ''}, ${item['state'] ?? ''}\nValid: ${item['from'] ?? 'N/A'} to ${item['to'] ?? 'N/A'}\n${item['details'] ?? ''}',
            ),
          ),
        ),
    ],
    const SizedBox(height: 16),
    for (final kind in ['Deal', 'Coupon'])
      FilledButton(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => OfferPage(
                kind: kind,
                username: widget.username,
                profile: widget.profile,
              ),
            ),
          );
          if (saved == true) await loadOffers();
        },
        child: Text('Publish ${kind}s'),
      ),
    TextButton(onPressed: loadOffers, child: const Text('Refresh offers')),
  ];
}
