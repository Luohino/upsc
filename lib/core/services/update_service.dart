import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constant/app_constants.dart';

class UpdateService {
  // TODO: Replace with your endpoint that returns latest version info
  // Example JSON:
  // {
  //   "latestVersion": "1.1.0+5",
  //   "minSupportedVersion": "1.0.0+2",
  //   "apkUrl": "https://example.com/app/upsc-1.1.0+5.apk",
  //   "mandatory": true,
  //   "changelog": "Bug fixes and improvements"
  // }
  static const String updateConfigUrl =
      "https://raw.githubusercontent.com/Luohino/Pinsry/main/android.json"; // GitHub raw JSON

  static Future<void> checkAtLaunch() async {
    if (!Platform.isAndroid) {
      debugPrint('[Update] Skipping: non-Android platform');
      return;
    }

    // If custom endpoint configured, use OTA flow; else fallback to Play Core
    if (updateConfigUrl.isNotEmpty) {
      await _checkCustomOta();
    } else {
      debugPrint(
          '[Update] No OTA endpoint set; skipping update check (configure updateConfigUrl).');
    }
  }

  static Future<void> _checkCustomOta() async {
    try {
      debugPrint(
          '[Update][OTA] Fetching update config from: ' + updateConfigUrl);
      final resp = await http
          .get(Uri.parse(updateConfigUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint('[Update][OTA] Config HTTP ' + resp.statusCode.toString());
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      final latest = (data['latestVersion'] ?? '').toString();
      final minSupported = (data['minSupportedVersion'] ?? '').toString();
      final apkUrl = (data['apkUrl'] ?? '').toString();
      final mandatory = (data['mandatory'] ?? false) == true;
      final changelog = (data['changelog'] ?? '').toString();

      if (apkUrl.isEmpty || latest.isEmpty) {
        debugPrint(
            '[Update][OTA] Invalid config: missing apkUrl/latestVersion');
        return;
      }

      final info = await PackageInfo.fromPlatform();
      final current = info.version + '+' + info.buildNumber;
      debugPrint('[Update][OTA] current=' +
          current +
          ' latest=' +
          latest +
          ' min=' +
          minSupported +
          ' mandatory=' +
          mandatory.toString());

      final needsUpdate = _isNewer(latest, current);
      final belowMin =
          minSupported.isNotEmpty && _isNewer(minSupported, current);
      final force = mandatory || belowMin;

      if (needsUpdate) {
        debugPrint('[Update][OTA] Update required. Force=' + force.toString());
        _showBlockingUpdateDialog(
            apkUrl: apkUrl, changelog: changelog, force: force);
      } else {
        debugPrint('[Update][OTA] Already up to date');
      }
    } catch (e) {
      debugPrint('[Update][OTA] Error: ' + e.toString());
    }
  }

  static bool _isNewer(String a, String b) {
    // Compare semver+build like 1.2.3+4
    int buildA = 0, buildB = 0;
    final pa = a.split('+');
    final pb = b.split('+');
    final va = (pa.isNotEmpty ? pa[0] : '0');
    final vb = (pb.isNotEmpty ? pb[0] : '0');
    if (pa.length > 1) buildA = int.tryParse(pa[1]) ?? 0;
    if (pb.length > 1) buildB = int.tryParse(pb[1]) ?? 0;

    int cmp = _compareVersionCore(va, vb);
    if (cmp != 0) return cmp > 0;
    return buildA > buildB;
  }

  static int _compareVersionCore(String va, String vb) {
    final as = va.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bs = vb.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = as.length > bs.length ? as.length : bs.length;
    for (int i = 0; i < len; i++) {
      final ai = i < as.length ? as[i] : 0;
      final bi = i < bs.length ? bs[i] : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  static void _showBlockingUpdateDialog(
      {required String apkUrl, String? changelog, required bool force}) {
    final context = AppConstants.navigatorKey.currentContext;
    if (context == null) {
      debugPrint('[Update][OTA] No context available to show dialog');
      return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'update',
      pageBuilder: (_, __, ___) {
        return _UpdateDialog(
            apkUrl: apkUrl, changelog: changelog, force: force);
      },
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String apkUrl;
  final String? changelog;
  final bool force;
  const _UpdateDialog(
      {required this.apkUrl, this.changelog, required this.force});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0.0;
  String _status = 'Preparing…';
  Stream<OtaEvent>? _stream;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    debugPrint('[Update][OTA] Starting download: ' + widget.apkUrl);
    try {
      setState(() {
        _status = 'Downloading…';
      });
      _stream = OtaUpdate().execute(
        widget.apkUrl,
        destinationFilename: 'update.apk',
      );
      _stream!.listen((event) {
        debugPrint('[Update][OTA] event=' +
            event.status.toString() +
            ' value=' +
            (event.value ?? ''));
        if (event.status == OtaStatus.DOWNLOADING) {
          final v = double.tryParse(event.value ?? '0') ?? 0;
          setState(() {
            _progress = v / 100.0;
          });
        } else if (event.status == OtaStatus.INSTALLING) {
          setState(() {
            _status = 'Installing…';
          });
        } else if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
          setState(() {
            _status = 'Grant install permission in settings';
          });
        } else if (event.status == OtaStatus.ALREADY_RUNNING_ERROR) {
          setState(() {
            _status = 'Update already running…';
          });
        } else if (event.status == OtaStatus.INSTALLING) {
          setState(() {
            _status = 'Installing…';
          });
        } else if (event.status == OtaStatus.INTERNAL_ERROR) {
          setState(() {
            _status = 'Error. Try again later.';
          });
        }
      });
    } catch (e) {
      debugPrint('[Update][OTA] Start error: ' + e.toString());
      setState(() {
        _status = 'Failed to start update';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Update required',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if ((widget.changelog ?? '').isNotEmpty)
                  SizedBox(
                    height: 80,
                    child:
                        SingleChildScrollView(child: Text(widget.changelog!)),
                  ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress),
                const SizedBox(height: 8),
                Text(_status),
                const SizedBox(height: 12),
                if (!widget.force)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('Later'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _startDownload,
                        child: const Text('Update now'),
                      ),
                    ],
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
