part of belt.io;

class QuickTerminalServer {
  final String executable;
  final List<String> args;

  HttpServer _server;
  Process _process;
  Stream<List<int>> _stdout;
  Stream<List<int>> _stderr;

  QuickTerminalServer(this.executable, this.args);

  Future startInsecureServer({int port: 8022, host: "0.0.0.0", String ws: "/ws"}) async {
    await useHttpServer(await HttpServer.bind(host, port), ws: ws);
  }

  Future useHttpServer(HttpServer server, {bool registerHandler: true, String ws: "/ws"}) async {
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

  Future stopHttpServer() async {
    if (_server != null) {
      await _server.close();
      _server = null;
    }
  }

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

class QuickTerminalClient {
  final String url;

  WebSocket _socket;
  int _exit = -1;

  QuickTerminalClient(this.url);

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

  Future disconnect() async {
    _socket.close();
  }

  void onConnected() {
    ProcessSignal.SIGINT.watch().listen((sig) {
      send(4, []);
    });

    stdin.lineMode = false;
    stdin.echoMode = false;
    stdin.listen((data) {
      send(3, data);
    });

    var env = new Map.from(Platform.environment);
    env["LINES"] = stdout.terminalLines.toString();
    env["COLUMNS"] = stdout.terminalColumns.toString();

    send(5, UTF8.encode(JSON.encode({
      "env": env
    })));
  }

  void send(int id, List<int> data) {
    var out = [id];
    out.addAll(data);
    if (_socket != null) {
      _socket.add(out);
    }
  }

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

  void onStandardOut(List<int> data) {
    stdout.add(data);
  }

  void onStandardError(List<int> data) {
    stderr.add(data);
  }

  void onDisconnected(int exitCode) {
    exit(exitCode);
  }
}
