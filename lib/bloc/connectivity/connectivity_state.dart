part of 'connectivity_cubit.dart';

enum ConnectivityStatus { online, offline }

class ConnectivityState extends Equatable {
  const ConnectivityState({
    required this.status,
    this.justRestored = false,
  });

  final ConnectivityStatus status;
  final bool justRestored; // true briefly right after the connection returns

  bool get isOffline => status == ConnectivityStatus.offline;

  @override
  List<Object?> get props => [status, justRestored];
}
