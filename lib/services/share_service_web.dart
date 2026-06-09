// Web implementation — uses dart:html to open URLs
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;

void openUrl(String url) {
  html.window.open(url, '_self');
}
