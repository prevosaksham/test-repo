import 'package:device_info_plus/device_info_plus.dart';

class GvVersions{

  String? versionRelease;
  String? versionCode;

  static Future<String> find() async {
    var info = await DeviceInfoPlugin().androidInfo;
    return info.version.release.toString();
  }
}