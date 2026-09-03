import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_config.dart';

/// Wraps the Socket.io connection to hq-server for live queue-status pushes.
///
/// Mirrors `ClinicSocketService` in hq-tabapp — the server mounts Socket.io
/// on the same HTTP server as the REST API (see server.js) and broadcasts
/// every queue mutation to the `clinic_<id>` room a client joins via
/// `join_clinic`. Previously this app only found out about being called,
/// requeued, etc. on the next 15-second poll; joining the room lets the
/// queue-status screen react the instant the server emits the event.
///
/// Note: the server does NOT emit a single generic `queue_updated` event —
/// each mutation in queueController.js emits its own event name to the
/// clinic room (queue_entry_added, patient_called, service_started,
/// queue_completed, patient_skipped, patient_noshow, queue_cancelled,
/// walkin_added, queue_requeued) plus a catch-all `global_queue_change` to
/// everyone. We listen for all of them and treat any as "something
/// changed, refresh" — same approach as the tablet app.
class QueueSocketService {
  static const _queueEventNames = [
    'queue_entry_added',
    'patient_called',
    'service_started',
    'queue_completed',
    'patient_skipped',
    'patient_noshow',
    'queue_cancelled',
    'walkin_added',
    'queue_requeued',
    'global_queue_change',
  ];

  IO.Socket? _socket;
  String? _joinedId;

  bool get isConnected => _socket?.connected ?? false;

  /// Connects (if not already connected with this [id]) and calls
  /// [onUpdated] whenever the server emits a matching event. Safe to call
  /// repeatedly — it no-ops if already joined with the same [id].
  ///
  /// [joinEvent] defaults to 'join_clinic' (queue updates, room
  /// `clinic_<id>`) — pass 'join_user' to instead join a patient's own
  /// room (`user_<id>`) for account-level pushes like a patient-type
  /// approval, which aren't tied to any one clinic. [eventNames] lets
  /// that second use reuse this same wrapper instead of a duplicate class.
  void connect(
    String id, {
    required void Function(dynamic data) onUpdated,
    void Function()? onConnected,
    void Function()? onDisconnected,
    String joinEvent = 'join_clinic',
    List<String> eventNames = _queueEventNames,
  }) {
    if (_socket != null && _joinedId == id && _socket!.connected) {
      return;
    }
    disconnect();
    _joinedId = id;

    // ApiConfig.baseUrl includes a trailing /api for this app's REST calls
    // (see api_config.dart) — Socket.io needs the bare server origin.
    final origin = ApiConfig.baseUrl.replaceAll(RegExp(r'/api/?$'), '');

    _socket = IO.io(
      origin,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      _socket!.emit(joinEvent, id);
      onConnected?.call();
    });

    _socket!.onDisconnect((_) => onDisconnected?.call());

    for (final event in eventNames) {
      _socket!.on(event, onUpdated);
    }

    _socket!.connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _joinedId = null;
  }
}
