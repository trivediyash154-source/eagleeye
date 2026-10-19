import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/states.dart';
import '../features/analytics/analytics_page.dart';
import '../features/dashboard/overview_page.dart';
import '../features/detection/detection_page.dart';
import '../features/diagnostics/model_diagnostics_page.dart';
import '../features/diagnostics/system_health_page.dart';
import '../features/drawing/drawing_page.dart';
import '../features/evidence/evidence_page.dart';
import '../features/history/history_page.dart';
import '../features/inspections/live_inspection_page.dart';
import '../features/inspections/new_inspection_page.dart';
import '../features/inspections/workspace_page.dart';
import '../features/landing/landing_page.dart';
import '../features/ocr/ocr_page.dart';
import '../features/reports/reports_page.dart';
import '../features/review/review_queue_page.dart';
import '../features/settings/settings_page.dart';
import 'shell.dart';

/// Route table. Inspection-scoped screens take `i` (inspection id) and `v` (version number)
/// query parameters so every view is linkable.
class NavItem {
  const NavItem(this.path, this.label, this.icon, this.group);
  final String path;
  final String label;
  final IconData icon;
  final String group;
}

const navItems = <NavItem>[
  NavItem('/console', 'Overview', Icons.space_dashboard_outlined, 'Operate'),
  NavItem('/console/new', 'New Inspection', Icons.add_box_outlined, 'Operate'),
  NavItem('/console/live', 'Live Inspection', Icons.sensors_rounded, 'Operate'),
  NavItem('/console/workspace', 'Inspection Workspace', Icons.view_quilt_outlined, 'Operate'),
  NavItem('/console/drawing', 'Drawing Intelligence', Icons.architecture_rounded, 'Analyze'),
  NavItem('/console/detection', 'Component Detection', Icons.center_focus_weak_rounded, 'Analyze'),
  NavItem('/console/ocr', 'OCR & Label Verification', Icons.text_fields_rounded, 'Analyze'),
  NavItem('/console/evidence', 'Evidence Explorer', Icons.photo_library_outlined, 'Analyze'),
  NavItem('/console/review', 'Review Queue', Icons.fact_check_outlined, 'Assure'),
  NavItem('/console/history', 'Inspection History', Icons.history_rounded, 'Assure'),
  NavItem('/console/analytics', 'Analytics & Insights', Icons.insights_rounded, 'Assure'),
  NavItem('/console/reports', 'Reports & Exports', Icons.picture_as_pdf_outlined, 'Assure'),
  NavItem('/console/models', 'Model Diagnostics', Icons.memory_rounded, 'System'),
  NavItem('/console/health', 'System Health', Icons.monitor_heart_outlined, 'System'),
  NavItem('/console/settings', 'Settings', Icons.tune_rounded, 'System'),
];

NavItem? navFor(String location) {
  final path = Uri.parse(location).path;
  if (path == '/console') return navItems.first;
  return navItems.where((n) => n.path != '/console' && path.startsWith(n.path)).firstOrNull;
}

int? _int(String? s) => s == null ? null : int.tryParse(s);

Page<void> _page(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: EE.med,
      reverseTransitionDuration: EE.fast,
      transitionsBuilder: (context, anim, _, child) {
        if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
        final a = CurvedAnimation(parent: anim, curve: EE.curve);
        return FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(a), child: child),
        );
      },
    );

GoRouter buildRouter() => GoRouter(
      initialLocation: '/console',
      errorPageBuilder: (c, s) => _page(s, _NotFoundPage(location: s.uri.path)),
      routes: [
        // The app opens straight into the console; the product overview lives at /welcome.
        GoRoute(path: '/', redirect: (_, _) => '/console'),
        GoRoute(path: '/welcome', pageBuilder: (c, s) => _page(s, const LandingPage())),
        GoRoute(path: '/landing', redirect: (_, _) => '/welcome'),
        ShellRoute(
          builder: (context, state, child) => ConsoleShell(location: state.uri.toString(), child: child),
          routes: [
            GoRoute(path: '/console', pageBuilder: (c, s) => _page(s, const OverviewPage())),
            GoRoute(path: '/console/new', pageBuilder: (c, s) => _page(s, const NewInspectionPage())),
            GoRoute(path: '/console/live', pageBuilder: (c, s) => _page(s, LiveInspectionPage(jobId: s.uri.queryParameters['job']))),
            GoRoute(
              path: '/console/workspace',
              pageBuilder: (c, s) => _page(s, WorkspacePage(inspectionId: s.uri.queryParameters['i'], versionNo: _int(s.uri.queryParameters['v']), findingId: s.uri.queryParameters['f'])),
            ),
            GoRoute(path: '/console/drawing', pageBuilder: (c, s) => _page(s, DrawingPage(inspectionId: s.uri.queryParameters['i'], versionNo: _int(s.uri.queryParameters['v'])))),
            GoRoute(path: '/console/detection', pageBuilder: (c, s) => _page(s, DetectionPage(inspectionId: s.uri.queryParameters['i'], versionNo: _int(s.uri.queryParameters['v'])))),
            GoRoute(path: '/console/ocr', pageBuilder: (c, s) => _page(s, OcrPage(inspectionId: s.uri.queryParameters['i'], versionNo: _int(s.uri.queryParameters['v'])))),
            GoRoute(path: '/console/evidence', pageBuilder: (c, s) => _page(s, EvidencePage(inspectionId: s.uri.queryParameters['i']))),
            GoRoute(path: '/console/review', pageBuilder: (c, s) => _page(s, const ReviewQueuePage())),
            GoRoute(path: '/console/history', pageBuilder: (c, s) => _page(s, HistoryPage(inspectionId: s.uri.queryParameters['i']))),
            GoRoute(path: '/console/analytics', pageBuilder: (c, s) => _page(s, const AnalyticsPage())),
            GoRoute(path: '/console/reports', pageBuilder: (c, s) => _page(s, ReportsPage(inspectionId: s.uri.queryParameters['i']))),
            GoRoute(path: '/console/models', pageBuilder: (c, s) => _page(s, const ModelDiagnosticsPage())),
            GoRoute(path: '/console/health', pageBuilder: (c, s) => _page(s, const SystemHealthPage())),
            GoRoute(path: '/console/settings', pageBuilder: (c, s) => _page(s, const SettingsPage())),
          ],
        ),
      ],
    );

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: EE.bg0,
        body: EmptyState(
          icon: Icons.explore_off_outlined,
          title: 'Page not found',
          message: 'Nothing lives at $location.',
          action: FilledButton.icon(
            onPressed: () => context.go('/console'),
            icon: const Icon(Icons.space_dashboard_outlined, size: 16),
            label: const Text('Open the console'),
          ),
        ),
      );
}

/// Helpers to build links between screens.
String workspaceLink(String inspectionId, {int? version, String? finding}) =>
    '/console/workspace?i=$inspectionId${version != null ? '&v=$version' : ''}${finding != null ? '&f=$finding' : ''}';
String scopedLink(String base, String inspectionId, {int? version}) => '$base?i=$inspectionId${version != null ? '&v=$version' : ''}';
