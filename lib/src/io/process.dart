part of belt.io;

/// A callback handler for [BetterProcessResult] objects.
typedef ProcessResultHandler(BetterProcessResult result);

/// A callback handler for [Process] objects.
typedef ProcessHandler(Process process);

/// A callback handler for process output data.
typedef ProcessOutputHandler(data);

/// A callback handler to retrieve the [ProcessAdapterReferences] adapter.
typedef ProcessAdapterHandler(ProcessAdapterReferences adapter);

/// A callback handler for process logging.
typedef ProcessLogHandler(String message);

Stdin get _stdin => stdin;

/// An improved process result with combined stdout + stderr output.
class BetterProcessResult extends ProcessResult {
  /// The full process output.
  final output;

  BetterProcessResult(int pid, int exitCode, stdout, stderr, this.output)
    : super(pid, exitCode, stdout, stderr);

  @override
  String toString() => output.toString().trim();
}

/// A class to pass in flags in the references for
/// the [executeCommand] method.
class ProcessAdapterFlags {
  /// Should we inherit stdio?
  bool inherit = false;

  /// Output log file.
  File logFile;

  /// Logging callback handler.
  ProcessLogHandler logHandler;
}

/// Process references.
class ProcessAdapterReferences {
  /// The process result.
  BetterProcessResult result;

  /// Process object.
  Process process;

  /// Process flags.
  ProcessAdapterFlags flags = new ProcessAdapterFlags();

  /// Handle when the process result is ready.
  Future<BetterProcessResult> get onResultReady {
    if (result != null) {
      return new Future.value(result);
    } else {
      var c = new Completer<BetterProcessResult>();
      _onResultReady.add(c.complete);
      return c.future;
    }
  }

  /// Handle when the process is ready.
  Future<Process> get onProcessReady {
    if (process != null) {
      return new Future.value(process);
    } else {
      var c = new Completer<Process>();
      _onProcessReady.add(c.complete);
      return c.future;
    }
  }

  List<ProcessResultHandler> _onResultReady = <ProcessResultHandler>[];
  List<ProcessHandler> _onProcessReady = <ProcessHandler>[];

  /// Pushes the process into the reference.
  void pushProcess(Process process) {
    this.process = process;
    while (_onProcessReady.isNotEmpty) {
      _onProcessReady.removeAt(0)(process);
    }
  }

  /// Pushes the result into the reference.
  void pushResult(BetterProcessResult result) {
    this.result = result;
    while (_onResultReady.isNotEmpty) {
      _onResultReady.removeAt(0)(result);
    }
  }
}

/// Execute a Command.
///
/// [executable] is the name or path to the executable to run.
/// [args] is an optional list of arguments for the executable.
/// [workingDirectory] is a path to the directory to execute the command in.
/// [includeParentEnvironment] specifies whether the process should inherit the current environment.
/// [runInShell] specified whether the process should run in a command line shell.
/// [stdin] is an instance of any of the following:
/// - [String]
/// - [List<int>]
/// - [Stream<String>]
/// - [Stream<List<int>>]
/// - [File]
/// that will be passed as the input of the command.
///
/// [handler] specifies a callback for the [Process] object.
/// [stdoutHandler] specifies a callback for stdout data.
/// [stderrHandler] specifies a callback for stderr data.
/// [outputHandler] specifies a callback for any output data.
/// [outputFile] specifies a file to write log data to.
/// [inherit] specifies whether to write data to the stdout/stderr of the current process.
/// [writeToBuffer] specifies whether to write output to buffers for the process result.
/// [binary] specifies whether to treat the process output like binary data.
/// [resultHandler] specifies a callback for the [BetterProcessResult] instance.
/// [inheritStdin] specifies whether the current process stdin should be piped to the process.
/// [logHandler] specifies a callback for any logging output.
/// [sudo] specifies whether to run the command as root if possible or not.
/// [tty] specifies whether to attempt to emulate a TTY or not.
/// [refs] specifies the [ProcessAdapterReferences] instance.
///
/// [refs] can also be specified using the zone value `belt.io.process.ref`.
Future<BetterProcessResult> executeCommand(
  String executable,
  {
    List<String> args: const [],
    String workingDirectory,
    Map<String, dynamic> environment,
    bool includeParentEnvironment: true,
    bool runInShell: false,
    stdin,
    ProcessHandler handler,
    ProcessOutputHandler stdoutHandler,
    ProcessOutputHandler stderrHandler,
    ProcessOutputHandler outputHandler,
    File outputFile,
    bool inherit: false,
    bool writeToBuffer: true,
    bool binary: false,
    ProcessResultHandler resultHandler,
    bool inheritStdin: false,
    ProcessLogHandler logHandler,
    bool sudo: false,
    bool tty: false,
    ProcessAdapterReferences refs
  }) async {
  if (args == null) {
    args = <String>[];
  }

  {
    if (environment == null) {
      environment = <String, dynamic>{};
    }

    var env = <String, dynamic>{};

    for (String key in environment.keys) {
      env[key] = environment[key].toString();
    }

    environment = env;
  }

  args = args.map((arg) => arg.toString()).toList();

  if (sudo && BeltPlatform.isUnix && await isCommandInstalled("sudo")) {
    args.insert(0, executable);
    executable = "sudo";
  }

  if (tty && BeltPlatform.isUnix && await isCommandInstalled("command")) {
    args.insert(0, executable);
    executable = "command";

    if (!environment.containsKey("TERM")) {
      environment["TERM"] = "xterm";
    }
  }

  ProcessAdapterReferences refs = Zone.current["belt.io.process.ref"];

  if (refs != null) {
    outputFile = outputFile != null ? outputFile : refs.flags.logFile;
    logHandler = logHandler != null ? logHandler : refs.flags.logHandler;
  }

  IOSink raf;

  if (outputFile != null) {
    if (!(await outputFile.exists())) {
      await outputFile.create(recursive: true);
    }

    raf = await outputFile.openWrite(mode: FileMode.APPEND);
  }

  try {
    Process process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell
    );

    var id = process.pid.toString();

    if (refs != null) {
      refs.pushProcess(process);
      inherit = inherit || refs.flags.inherit;
    }

    if (raf != null) {
      await raf.writeln(
        "[${_currentTimestamp}][${id}] == Executing ${executable}"
          " with arguments ${args} (pid: ${process.pid}) =="
      );
    }

    if (logHandler != null) {
      logHandler(
        "[${_currentTimestamp}][${id}] == Executing ${executable}"
          " with arguments ${args} (pid: ${process.pid}) =="
      );
    }

    var buff = new StringBuffer();
    var ob = new StringBuffer();
    var eb = new StringBuffer();

    var obytes = <int>[];
    var ebytes = <int>[];
    var sbytes = <int>[];

    if (!binary) {
      process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((str) async {
        if (writeToBuffer) {
          ob.writeln(str);
          buff.writeln(str);
        }

        if (stdoutHandler != null) {
          stdoutHandler(str);
        }

        if (outputHandler != null) {
          outputHandler(str);
        }

        if (inherit) {
          stdout.writeln(str);
        }

        if (raf != null) {
          await raf.writeln("[${_currentTimestamp}][${id}] ${str}");
        }

        if (logHandler != null) {
          logHandler("[${_currentTimestamp}][${id}] ${str}");
        }
      });

      process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((str) async {
        if (writeToBuffer) {
          eb.writeln(str);
          buff.writeln(str);
        }

        if (stderrHandler != null) {
          stderrHandler(str);
        }

        if (outputHandler != null) {
          outputHandler(str);
        }

        if (inherit) {
          stderr.writeln(str);
        }

        if (raf != null) {
          await raf.writeln("[${_currentTimestamp}][${id}] ${str}");
        }

        if (logHandler != null) {
          logHandler("[${_currentTimestamp}][${id}] ${str}");
        }
      });
    } else {
      process.stdout.listen((bytes) {
        obytes.addAll(bytes);
        sbytes.addAll(bytes);
      });

      process.stderr.listen((bytes) {
        obytes.addAll(bytes);
        ebytes.addAll(bytes);
      });
    }

    if (handler != null) {
      handler(process);
    }

    if (stdin != null) {
      if (stdin is File) {
        stdin = stdin.openRead();
      }

      if (stdin is Stream) {
        stdin.listen(process.stdin.add, onDone: process.stdin.close);
      } else if (stdin is List) {
        process.stdin.add(stdin);
      } else {
        process.stdin.write(stdin);
        await process.stdin.close();
      }
    } else if (inheritStdin) {
      _stdin.listen(process.stdin.add, onDone: process.stdin.close);
    }

    var code = await process.exitCode;
    await new Future.delayed(const Duration(milliseconds: 1));
    var pid = process.pid;

    if (raf != null) {
      await raf.writeln(
        "[${_currentTimestamp}][${id}] == Exited with status ${code} =="
      );
      await raf.flush();
      await raf.close();
    }

    if (logHandler != null) {
      logHandler(
        "[${_currentTimestamp}][${id}] == Exited with status ${code} =="
      );
    }

    var result = new BetterProcessResult(
      pid,
      code,
      binary ? sbytes : ob.toString(),
      binary ? ebytes : eb.toString(),
      binary ? obytes : buff.toString()
    );

    if (resultHandler != null) {
      resultHandler(result);
    }

    if (refs != null) {
      refs.pushResult(result);
    }

    return result;
  } finally {
    if (raf != null) {
      await raf.flush();
      await raf.close();
    }
  }
}

String get _currentTimestamp => new DateTime.now().toString();
