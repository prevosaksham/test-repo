import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../theme/app_colors.dart';

/// ---------------------------------------------------------------------------
/// Static demo data for the RM dashboard flow. Swap these for API-backed data
/// later — the widgets only depend on these model shapes.
/// ---------------------------------------------------------------------------

class RmUser {
  const RmUser({required this.name, required this.notifications});
  final String name;
  final int notifications;
}

class StatCard {
  const StatCard({required this.icon, required this.value, required this.label});
  final String icon; // asset path
  final String value;
  final String label;
}

class CallTask {
  const CallTask({
    required this.leadId,
    required this.leadName,
    required this.mobile,
    required this.callDateTime,
  });
  final String leadId;
  final String leadName;
  final String mobile;
  final String callDateTime;
}

class VisitTask {
  const VisitTask({
    required this.leadId,
    required this.leadName,
    required this.mobile,
    required this.dealer,
    required this.visitDateTime,
  });
  final String leadId;
  final String leadName;
  final String mobile;
  final String dealer;
  final String visitDateTime;
}

/// A lead's pipeline stage — drives the badge colour + icon on My Leads.
enum LeadStage { fresh, kyc, fieldInvestigation }

extension LeadStageUi on LeadStage {
  String get label => switch (this) {
        LeadStage.fresh => 'New',
        LeadStage.kyc => 'Application & KYC',
        LeadStage.fieldInvestigation => 'Field Investigation',
      };

  bool get showCheck => this != LeadStage.fresh;

  Color get fg => switch (this) {
        LeadStage.fresh => AppColors.purple,
        _ => AppColors.chartApproved,
      };

  Color get bg => switch (this) {
        LeadStage.fresh => const Color(0x1A5B3FA0),
        _ => const Color(0x1A2EA66B),
      };
}

class Lead {
  const Lead({
    required this.leadId,
    required this.name,
    required this.phone,
    required this.location,
    required this.stage,
    required this.nextActivity,
    this.manageEnabled = true,
  });
  final String leadId;
  final String name;
  final String phone;
  final String location;
  final LeadStage stage;
  final String nextActivity;
  final bool manageEnabled;
}

class MonthTrend {
  const MonthTrend(this.month, this.fresh, this.approved, this.inProgress);
  final String month;
  final int fresh;
  final int approved;
  final int inProgress;
  int get total => fresh + approved + inProgress;
}

class FunnelStage {
  const FunnelStage(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

/// Single access point for all demo content.
class DashboardData {
  DashboardData._();

  static const RmUser user = RmUser(name: 'Rohan Gaikwad', notifications: 3);

  static const List<StatCard> stats = [
    StatCard(icon: AppAssets.totalLeads, value: '100', label: 'Total Leads'),
    StatCard(
        icon: AppAssets.convertedLeads, value: '90', label: 'Converted Leads'),
    StatCard(
        icon: AppAssets.rejectedLeads, value: '10', label: 'Rejected Leads'),
    StatCard(
        icon: AppAssets.conversionRate, value: '90%', label: 'Conversion Rate'),
  ];

  static const List<CallTask> calls = [
    CallTask(
        leadId: 'LID123456',
        leadName: 'Neha Ajay Gupta',
        mobile: '+91 9876543210',
        callDateTime: '27 May 2026 12:00 PM'),
    CallTask(
        leadId: 'LID123456',
        leadName: 'Neha Ajay Gupta',
        mobile: '+91 9876543210',
        callDateTime: '27 May 2026 12:00 PM'),
  ];

  static const List<VisitTask> visits = [
    VisitTask(
        leadId: 'LID123456',
        leadName: 'Neha Ajay Gupta',
        mobile: '+91 9876543210',
        dealer: 'ABC Motors',
        visitDateTime: '27 May 2026 12:00 PM'),
    VisitTask(
        leadId: 'LID123456',
        leadName: 'Neha Ajay Gupta',
        mobile: '+91 9876543210',
        dealer: 'ABC Motors',
        visitDateTime: '27 May 2026 12:00 PM'),
  ];

  static const List<Lead> leads = [
    Lead(
        leadId: 'LID123456',
        name: 'Neha Ajay Gupta',
        phone: '+91 9876543210',
        location: 'Nagpur, Maharashtra',
        stage: LeadStage.fresh,
        nextActivity: 'Call & Visit'),
    Lead(
        leadId: 'LID123456',
        name: 'Neha Ajay Gupta',
        phone: '+91 9876543210',
        location: 'Nagpur, Maharashtra',
        stage: LeadStage.kyc,
        nextActivity: 'Bureau Check',
        manageEnabled: false),
    Lead(
        leadId: 'LID123456',
        name: 'Neha Ajay Gupta',
        phone: '+91 9876543210',
        location: 'Nagpur, Maharashtra',
        stage: LeadStage.fieldInvestigation,
        nextActivity: 'Pre-disbursal Uploads'),
  ];

  static const List<MonthTrend> trend = [
    MonthTrend('Jun', 20, 40, 60),
    MonthTrend('May', 20, 40, 60),
    MonthTrend('Apr', 20, 40, 60),
    MonthTrend('Mar', 20, 40, 60),
    MonthTrend('Feb', 20, 40, 60),
    MonthTrend('Jan', 20, 40, 60),
  ];

  static const List<FunnelStage> funnel = [
    FunnelStage('Application & KYC', 80, AppColors.purple),
    FunnelStage('Loan Approved', 70, AppColors.statusRed),
    FunnelStage('Field Investigation', 50, AppColors.chartProgress),
    FunnelStage('Pre Disbursal', 50, AppColors.statusBlue),
    FunnelStage('Disbursement', 10, AppColors.chartApproved),
  ];
}
