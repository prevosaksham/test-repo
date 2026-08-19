part of 'lead_preview_bloc.dart';

abstract class LeadPreviewEvent extends Equatable {
  const LeadPreviewEvent();

  @override
  List<Object?> get props => [];
}

/// Load the resume/preview state for [leadId].
class LeadPreviewRequested extends LeadPreviewEvent {
  const LeadPreviewRequested(this.leadId);
  final String leadId;

  @override
  List<Object?> get props => [leadId];
}
