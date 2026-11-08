# Arrivio Android prototype

This Flutter app uses the same service endpoints as the web prototype. The
login screen includes user registration; merchant registration and the Arrivio
dashboard remain on the web. Existing user and merchant accounts can access
their respective mobile screens.

**Prototype only:** the current backend flow looks up accounts by username and
does not verify a password. Do not distribute this app or use it for real
accounts until authentication and authorization are implemented on the server.
The Android application ID is the Flutter-generated example ID and should be
changed before release.

## Run and build

From this directory:

```sh
flutter test
flutter run -d <device-id>
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
It is for testing, not a Play Store release. The service endpoints must be
available for login, registration, merchant search, and merchant offers.
After a destination is resolved, the app asks for an occasion (or allows
skipping it) and sends it to the distance service. The app warns when the
service does not confirm that occasion ranking was applied.
The nearby list shows only merchants with active deals or coupons returned by
the distance service. Tap a deal or coupon badge to see its details. If offer
data is missing, the app warns that the results may be incomplete.

To share a destination from Google Maps, use Share and select Arrivio. If
needed, log in as a user; the shared link is placed in the destination field.
Select Set destination to resolve it and choose an occasion. Android controls
the order of share targets, so Arrivio may appear under More.
