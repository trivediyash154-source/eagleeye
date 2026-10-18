import 'package:url_launcher/url_launcher.dart';

/// Opens a backend file URL. Downloads are served with Content-Disposition: attachment,
/// so the browser saves them rather than navigating away.
Future<bool> openUrl(String url, {bool newTab = true}) => launchUrl(Uri.parse(url), webOnlyWindowName: newTab ? '_blank' : '_self');
