import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/network_info.dart';

part 'connectivity_state.dart';

/// App-wide online/offline monitor. Seeds with the current status, then listens
/// to [NetworkInfo.onStatusChange]. When the connection returns it sets
/// [ConnectivityState.justRestored] for a few seconds so the UI can flash a
/// "Back online" message, then settles back to a plain online state.
class ConnectivityCubit extends Cubit<ConnectivityState> {
  ConnectivityCubit([NetworkInfo? network])
      : _network = network ?? NetworkInfo(),
        super(const ConnectivityState(status: ConnectivityStatus.online)) {
    _init();
  }

  final NetworkInfo _network;
  StreamSubscription<bool>? _sub;
  Timer? _restoreTimer;
  Timer? _poll;

  Future<void> _init() async {
    final online = await _network.isConnected;
    if (isClosed) return;
    emit(ConnectivityState(
      status: online ? ConnectivityStatus.online : ConnectivityStatus.offline,
    ));
    _sub = _network.onStatusChange.listen(_onChange);
    // The connectivity stream only fires on radio/interface changes. When the
    // phone stays on the same Wi-Fi but the internet itself drops and returns
    // (router/WAN blip, or DNS not ready at the reconnect moment), that stream
    // may never fire — so the offline banner would get stuck. Re-verify the
    // real internet on a short interval so the banner recovers on its own.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _recheck());
  }

  Future<void> _recheck() async {
    if (isClosed) return;
    _onChange(await _network.isConnected);
  }

  void _onChange(bool online) {
    if (isClosed) return;
    if (!online) {
      _restoreTimer?.cancel();
      emit(const ConnectivityState(status: ConnectivityStatus.offline));
      return;
    }
    final wasOffline = state.status == ConnectivityStatus.offline;
    emit(ConnectivityState(
      status: ConnectivityStatus.online,
      justRestored: wasOffline,
    ));
    if (wasOffline) {
      _restoreTimer?.cancel();
      _restoreTimer = Timer(const Duration(seconds: 3), () {
        if (!isClosed) {
          emit(const ConnectivityState(status: ConnectivityStatus.online));
        }
      });
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _restoreTimer?.cancel();
    _poll?.cancel();
    return super.close();
  }
}
