// TEMPORARY preview harness to screenshot the eSign Pending / Success UI
// without walking the whole application flow. Delete after review.
import 'package:flutter/material.dart';
import 'core/device/app_device.dart';
import 'theme/app_colors.dart';
import 'data/models/lead_item.dart';
import 'dashboard/application/esign_pending_screen.dart';

const _dummyLead = LeadItem(
  id: '1',
  leadNo: 'L1',
  applicationNo: 'A1',
  name: 'Preview',
  mobile: '',
  email: '',
  city: '',
  state: '',
  status: LeadStatusInfo.empty,
  agentName: '',
  nextActivity: '',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDevice.init();
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppPalette.light.surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.deepOrange,
          primary: AppColors.primary,
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
        extensions: const [AppPalette.light],
      ),
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatelessWidget {
  const _PreviewHome();
  @override
  Widget build(BuildContext context) {
    void open(bool signed) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ESignPendingScreen(lead: _dummyLead, previewSigned: signed)));
    Widget btn(String label, Color color, bool signed) => Expanded(
          child: InkWell(
            onTap: () => open(signed),
            child: Container(
              color: color.withValues(alpha: 0.15),
              alignment: Alignment.center,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
            ),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            btn('PENDING', AppColors.amber, false),
            btn('SUCCESS', AppColors.success, true),
          ],
        ),
      ),
    );
  }
}
