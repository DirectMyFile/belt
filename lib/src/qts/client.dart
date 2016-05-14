part of belt.qts;

/// The Quick Terminal Client
class QuickTerminalClient {
  /// WebSocket Access URL
  final String url;

  WebSocket _socket;
  int _exit = -1;

  QuickTerminalClient(this.url);

  /// Connect to the Terminal Server
  Future connect() async {
    _socket = await WebSocket.connect(url);

    _socket.listen((data) {
      if (data is List) {
        onDataReceived(data);
      }
    });

    _socket.done.then((_) {
      onDisconnected(_exit);
    });

    onConnected();
  }

  /// Disconnect from the Terminal Server
  Future disconnect() async {
    _socket.close();
  }

  /// Handles connection startup.
  /// By Default:
  /// - Handles the SIGINT signal.
  /// - Sets `stdin.echoMode = false`.
  /// - Sets `stdin.lineMode = false`.
  /// - Pipes `stdin` to the server.
  /// - Sends the current environment to the server.
  void onConnected() {
    ProcessSignal.SIGINT.watch().listen((sig) {
      send(4, []);
    });

    stdin.lineMode = false;
    stdin.echoMode = false;
    stdin.listen((data) {
      send(3, data);
    });

    var env = new Map<String, String>.from(Platform.environment);

    if (stdout.hasTerminal) {
      env["LINES"] = stdout.terminalLines.toString();
      env["COLUMNS"] = stdout.terminalColumns.toString();
    }

    send(5, UTF8.encode(JSON.encode({
      "env": env
    })));
  }

  /// Send the data packet with the given [id] and binary [data].
  void send(int id, List<int> data) {
    var out = [id];
    out.addAll(data);
    if (_socket != null) {
      _socket.add(out);
    }
  }

  /// Handles the received data packets.
  void onDataReceived(List<int> data) {
    var a = data[0];
    var d = data.skip(1).toList();

    if (a == 1) {
      onStandardOut(d);
    } else if (a == 2) {
      onStandardError(d);
    } else if (a == 3) {
      _exit = d[0];
    }
  }

  /// Handles remote stdout data.
  /// By default pipes to local stdout.
  void onStandardOut(List<int> data) {
    stdout.add(data);
  }

  /// Handles remote stderr data.
  /// By default pipes to local stderr.
  void onStandardError(List<int> data) {
    stderr.add(data);
  }

  /// Handles remote disconnection.
  /// By default exits with the given [exitCode].
  void onDisconnected(int exitCode) {
    exit(exitCode);
  }
}
