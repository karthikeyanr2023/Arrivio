import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedDestination extends ChangeNotifier {
  SharedDestination({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('arrivio/shared_destination');

  final MethodChannel _channel;
  String? destination;
  String? error;
  bool _disposed = false;

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareAvailable') {
        await _receive();
      } else {
        throw MissingPluginException('Unknown share event: ${call.method}');
      }
    });
    await _receive();
  }

  Future<void> _receive() async {
    try {
      final text = await _channel.invokeMethod<String>('takeSharedText');
      if (_disposed || text == null) return;
      final match = RegExp(
        r'https?://[^\s<>]+',
        caseSensitive: false,
      ).firstMatch(text);
      if (match == null) {
        error = 'The shared text does not contain a link. Share a place from Google Maps.';
      } else {
        destination = match.group(0);
        error = null;
      }
      notifyListeners();
    } on PlatformException catch (e) {
      if (!_disposed) {
        error =
            'Unable to receive the shared destination: ${e.message ?? e.code}';
        notifyListeners();
      }
    } on MissingPluginException catch (e) {
      if (!_disposed) {
        error = 'Sharing is unavailable: ${e.message}';
        notifyListeners();
      }
    }
  }

  String? takeDestination() {
    final value = destination;
    destination = null;
    if (value != null) notifyListeners();
    return value;
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
