import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import '../database/database_helper.dart';
import '../database/data_db_helper.dart';

class WebSocketServer {
  HttpServer? _server;
  bool get isRunning => _server != null;
  String _serverIp = '0.0.0.0';
  final int _port = 8080;
  
  String get serverIp => _serverIp;
  int get port => _port;

  final Function(String) onLog;
  final Function() onStateChanged;

  final Lock _dbLock = Lock();

  WebSocketServer({required this.onLog, required this.onStateChanged});

  Future<void> getIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _serverIp = addr.address;
            onStateChanged();
            return;
          }
        }
      }
    } catch (e) {
      onLog('Failed to get IP address: $e');
    }
  }

  Future<void> start() async {
    if (isRunning) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      onStateChanged();
      onLog('Server started on $_serverIp:$_port');

      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/ws' || request.uri.path == '/db') {
          // Check for Authorization Header
          final authHeader = request.headers.value('authorization');
          if (authHeader == null || !authHeader.startsWith('Basic ')) {
            _rejectRequest(request, 'Missing or invalid Authorization header');
            return;
          }

          final encodedCredentials = authHeader.substring(6);
          try {
            final decoded = utf8.decode(base64.decode(encodedCredentials));
            final parts = decoded.split(':');
            if (parts.length != 2) throw Exception('Invalid format');
            
            final username = parts[0];
            final password = parts[1];

            // Verify with SQLite Database
            final isValid = await DatabaseHelper.instance.verifyCredentials(username, password);
            if (!isValid) {
              _rejectRequest(request, 'Invalid credentials');
              return;
            }

            // Route handling
            if (request.uri.path == '/ws') {
              try {
                WebSocket socket = await WebSocketTransformer.upgrade(request);
                onLog('Client connected: $username from ${request.connectionInfo?.remoteAddress.address}');
                socket.listen(
                  (message) {
                    onLog('[$username] Received: $message');
                    socket.add('Echo ($username): $message');
                  },
                  onDone: () {
                    onLog('Client disconnected: $username');
                  },
                  onError: (error) {
                    onLog('Error ($username): $error');
                  },
                );
              } catch (e) {
                onLog('Upgrade error: $e');
              }
            } else if (request.uri.path == '/db') {
              try {
                WebSocket socket = await WebSocketTransformer.upgrade(request);
                onLog('DB Client connected: $username');
                
                socket.listen((message) async {
                  try {
                    final payload = jsonDecode(message);
                    final method = payload['method'];
                    
                    final prefs = await SharedPreferences.getInstance();
                    final isTransaction = method == 'transaction';
                    
                    int fallbackTimeout = isTransaction 
                        ? (prefs.getInt('transaction_timeout_seconds') ?? 5)
                        : (prefs.getInt('query_timeout_seconds') ?? 5);
                        
                    int timeoutSeconds = payload['timeout_seconds'] ?? fallbackTimeout;
                    final timeout = Duration(seconds: timeoutSeconds);

                    if (method == 'query') {
                      final sql = payload['sql'];
                      final args = payload['args'] ?? [];
                      onLog('[$username] DB Read: $sql');
                      
                      try {
                        final db = await DataDatabaseHelper.instance.database;
                        final result = await db.rawQuery(sql, args).timeout(timeout);
                        socket.add(jsonEncode({"status": "success", "data": result}));
                      } catch(e) {
                        socket.add(jsonEncode({"status": "error", "message": e.toString()}));
                      }

                    } else if (method == 'execute') {
                      final sql = payload['sql'];
                      final args = payload['args'] ?? [];
                      onLog('[$username] DB Write: $sql');
                      
                      try {
                        final result = await _dbLock.synchronized(() async {
                          final db = await DataDatabaseHelper.instance.database;
                          return await db.rawInsert(sql, args).timeout(timeout);
                        });
                        socket.add(jsonEncode({"status": "success", "insertId_or_affectedRows": result}));
                      } catch(e) {
                        socket.add(jsonEncode({"status": "error", "message": e.toString()}));
                      }

                    } else if (method == 'transaction') {
                      final operations = payload['operations'] as List<dynamic>? ?? [];
                      onLog('[$username] DB Transaction: ${operations.length} ops');
                      
                      try {
                        final results = await _dbLock.synchronized(() async {
                          final db = await DataDatabaseHelper.instance.database;
                          return await db.transaction((txn) async {
                            List<dynamic> opResults = [];
                            for (var op in operations) {
                              final sql = op['sql'];
                              final args = op['args'] ?? [];
                              final res = await txn.rawInsert(sql, args);
                              opResults.add(res);
                            }
                            return opResults;
                          }).timeout(timeout);
                        });
                        socket.add(jsonEncode({"status": "success", "results": results}));
                      } catch(e) {
                        socket.add(jsonEncode({"status": "error", "message": "Transaction failed or timed out: ${e.toString()}"}));
                      }
                    } else {
                      socket.add(jsonEncode({"status": "error", "message": "Unknown method. Use 'query', 'execute', or 'transaction'."}));
                    }
                  } catch (e) {
                    socket.add(jsonEncode({"status": "error", "message": "Invalid JSON payload: ${e.toString()}"}));
                  }
                }, onDone: () {
                  onLog('DB Client disconnected: $username');
                });
              } catch (e) {
                onLog('DB Upgrade error: $e');
              }
            }

          } catch (e) {
            _rejectRequest(request, 'Invalid Base64 credentials');
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      onLog('Failed to start server: $e');
      _server = null;
      onStateChanged();
    }
  }

  void _rejectRequest(HttpRequest request, String reason) {
    onLog('Auth failed: $reason (${request.connectionInfo?.remoteAddress.address})');
    request.response.statusCode = HttpStatus.unauthorized;
    request.response.headers.add('WWW-Authenticate', 'Basic realm="WebSocket Server"');
    request.response.write('401 Unauthorized: $reason');
    request.response.close();
  }

  Future<void> stop() async {
    if (!isRunning) return;
    try {
      await _server?.close(force: true);
      _server = null;
      onStateChanged();
      onLog('Server stopped');
    } catch (e) {
      onLog('Failed to stop server: $e');
    }
  }
}
