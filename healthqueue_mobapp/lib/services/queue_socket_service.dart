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
  String? _joinedClinicId;

  bool get isConnected => _socket?.connected ?? false;

  /// Connects (if not already connected to this clinic's room) and calls
  /// [onQueueUpdated] whenever the server emits any queue-change event.
  /// Safe to call repeatedly — it no-ops if already joined to [clinicId].
  void connect(
    String clinicId, {
    required void Function(dynamic data) onQueueUpdated,
    void Function()? onConnected,
    void Function()? onDisconnected,
  }) {
    if (_socket != null && _joinedClinicId == clinicId && _socket!.connected) {
      return;
    }
    disconnect();
    _joinedClinicId = clinicId;

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
      _socket!.emit('join_clinic', clinicId);
      onConnected?.call();
    });

    _socket!.onDisconnect((_) => onDisconnected?.call());

    for (final event in _queueEventNames) {
      _socket!.on(event, onQueueUpdated);
    }

    _socket!.connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _joinedClinicId = null;
  }
}
