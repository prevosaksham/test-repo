part of 'lead_preview_bloc.dart';

enum LeadPreviewStatus { initial, loading, success, failure }

class LeadPreviewState extends Equatable {
  const LeadPreviewState({
    this.status = LeadPreviewStatus.initial,
    this.preview = LeadPreview.empty,
    this.errorMessage,
  });

  final LeadPreviewStatus status;
  final LeadPreview preview;
  final String? errorMessage;

  bool get isLoading =>
      status == LeadPreviewStatus.loading ||
      status == LeadPreviewStatus.initial;
  bool get isSuccess => status == LeadPreviewStatus.success;
  bool get isFailure => status == LeadPreviewStatus.failure;

  LeadPreviewState copyWith({
    LeadPreviewStatus? status,
    LeadPreview? preview,
    String? errorMessage,
  }) {
    return LeadPreviewState(
      status: status ?? this.status,
      preview: preview ?? this.preview,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, preview, errorMessage];
}
