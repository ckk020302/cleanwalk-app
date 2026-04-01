import 'package:flutter/material.dart';

import 'report_issue_page.dart';

class ReportPage extends StatelessWidget {
  static const routeName = '/report';

  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportIssuePage(
      source: 'map',
    );
  }
}