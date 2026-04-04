import 'package:url_launcher/url_launcher_string.dart';

Future<bool> openExternalUrl(String url) async {
  var opened = await launchUrlString(url, mode: LaunchMode.externalApplication);
  if (!opened) {
    opened = await launchUrlString(url, mode: LaunchMode.platformDefault);
  }
  return opened;
}
