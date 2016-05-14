part of belt.qts;

/// The Quick Terminal Server
class QuickTerminalServer {
  /// Executable to Run
  final String executable;

  /// Executable Arguments
  final List<String> args;

  HttpServer _server;
  Process _process;
  Stream<List<int>> _stdout;
  Stream<List<int>> _stderr;

  QuickTerminalServer(this.executable, this.args);

  /// Starts an insecure HTTP server on the given [port] and [host] serving the
  /// WebSocket interface at the given [ws] path.
  Future startInsecureServer({int port: 8022, host: "0.0.0.0", String ws: "/ws"}) async {
    await useHttpServer(await HttpServer.bind(host, port), ws: ws);
  }

  /// Uses the given HTTP [server] to handle requests.
  /// Serves the WebSocket interface at the given [ws] path.
  Future useHttpServer(HttpServer server, {String ws: "/ws"}) async {
    _server = server;

    _server.listen((HttpRequest request) async {
      if (request.uri.path == ws) {
        await handleClientSocket(await WebSocketTransformer.upgrade(request));
      } else {
        request.response
          ..statusCode = HttpStatus.NOT_FOUND
          ..writeln("Not Found.")
          ..close();
      }
    });
  }

  /// Stops the current HTTP Server.
  Future stopHttpServer() async {
    if (_server != null) {
      await _server.close();
      _server = null;
    }
  }

  /// Process the given client [socket].
  Future handleClientSocket(WebSocket socket) async {
    socket.listen((data) async {
      if (data is List) {
        var a = data[0];

        if (a == 3) {
          _process.stdin.add(data.skip(1).toList());
        } else if (a == 4) {
          _process.kill(ProcessSignal.SIGINT);
        } else if (a == 5) {
          var spec = UTF8.decode(data.skip(1).toList());
          var json = {};
          try {
            json = JSON.decode(spec);
          } catch (_) {
          }

          if (json is! Map) {
            json = {};
          }

          Map env = json["env"];

          if (env is! Map) {
            env = {};
          }

          env = _getEnvMap(env);

          if (_process == null) {
            await _doProcess(env);
          }

          _stdout.listen((data) {
            var out = [1];
            out.addAll(data);
            socket.add(out);
          });

          _stderr.listen((data) {
            var out = [2];
            out.addAll(data);
            socket.add(out);
          });
        }
      }
    });

    _sockets.add(socket);

    socket.done.then((_) {
      _sockets.remove(socket);
    });
  }

  Map _getEnvMap(Map env) {
    var out = {};

    _p(String k) {
      if (env[k] is String) {
        out[k] = env[k];
      }
    }

    _c(String k, String t) {
      if (env[k] is String) {
        out[t] = env[k];
      }
    }

    _p("TERM");
    _p("LANG");
    _p("LINES");
    _p("COLUMNS");
    _c("COLUMNS", "OVER_TERM_COL");
    _c("LINES", "OVER_TERM_LINES");

    return out;
  }

  Future _doProcess(Map<String, String> env) async {
    var _exe = "script";
    var _args = [];

    if (Platform.isMacOS) {
      _args.add("-q");
      _args.add("/dev/null");
      _args.add(executable);
      _args.addAll(args);
    } else if (Platform.isWindows) {
      _exe = executable;
    } else {
      _args.add("-qfc");
      _args.add("${executable} ${args.join(' ')}".trim());
      _args.add("/dev/null");
    }

    _process = await Process.start(_exe, _args, environment: env);
    _stdout = _process.stdout.asBroadcastStream();
    _stderr = _process.stderr.asBroadcastStream();

    _process.exitCode.then((int code) {
      while (_sockets.isNotEmpty) {
        WebSocket socket = _sockets.removeAt(0);
        socket.add([
          3,
          code.abs()
        ]);
        socket.close();
      }

      _process = null;
    });
  }

  List<WebSocket> _sockets = [];
}
