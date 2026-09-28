// kitchen_server — the queue a kitchen screen watches.
//
// Every other sample in this series works by asking. The screen calls a tool,
// gets an answer, draws it. That is fine for a screen somebody is holding, and
// wrong for a screen bolted to a wall: a kitchen display that only changes
// when it is asked will either ask constantly or be late.
//
// So the queue is a resource here, not a tool result, and the server says when
// it changed. The kitchen subscribes once and then does nothing at all until
// it is told.
//
// Run:  dart run bin/server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_server/mcp_server.dart';

import 'serve_bundle.dart';

const _queueUri = 'orders://queue';

Future<void> main(List<String> args) async {
  final result = await McpServer.createAndStart(
    config: McpServer.simpleConfig(name: 'Kitchen', version: '1.0.0'),
    transportConfig: transportFor(args),
  );

  result.fold(
    (server) {
      _Kitchen(server).register();
      // The screen next door: AppPlayer reads it from here.
      registerBundleUi(server, '../kitchen.mbd');
      server.onDisconnect.listen((_) => exit(0));
    },
    (error) {
      stderr.writeln('kitchen_server failed to start: $error');
      exit(1);
    },
  );
}


/// "1 order", "2 orders". A screen that says "1 orders" is a screen
/// nobody proofread.
String _plural(int n, String one) => "$n $one" + (n == 1 ? "" : "s");

class _Ticket {
  _Ticket(this.no, this.item);

  final int no;
  final String item;
  var done = false;
}

class _Kitchen {
  _Kitchen(this.server);

  final Server server;

  /// What the front of house would send in. In a real shop these arrive from
  /// the till; here the server plays them out on a timer so that the run is
  /// the same every time and the kitchen genuinely has nothing to do with
  /// when they appear.
  static const _incoming = [
    'Chicken salad',
    'Cold noodles',
    'Pork cutlet',
  ];

  final _tickets = <_Ticket>[];
  var _next = 71;
  Timer? _service;
  // Counted so a client can show that the screen never asked: reads happen
  // only when the server said the queue moved.
  var _reads = 0;
  var _told = 0;
  var _opens = 0;
  var _dones = 0;

  void register() {
    server.addResource(
      uri: _queueUri,
      name: 'Kitchen queue',
      description: 'Tickets the kitchen still has to make',
      mimeType: 'application/json',
      handler: (uri, params) async {
        _reads++;
        return ReadResourceResult(
        contents: [
          ResourceContentInfo(
              uri: _queueUri,
              mimeType: 'application/json',
              text: _queueJson()),
        ],
      );
      },
    );

    server.addTool(
      name: 'kitchen.open',
      description: 'Open the shift. Orders start arriving on their own.',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async {
        _opens++;
        _service?.cancel();
        var i = 0;
        _service = Timer.periodic(const Duration(milliseconds: 220), (t) {
          if (i >= _incoming.length) {
            t.cancel();
            return;
          }
          _tickets.add(_Ticket(_next++, _incoming[i++]));
          // The whole point. Nobody asked; the server says the queue moved.
          _told++;
          server.notifyResourceUpdated(_queueUri);
        });
        return CallToolResult(content: [
          TextContent(text: 'shift open — ${_plural(_incoming.length, 'order')} coming'),
        ]);
      },
    );

    server.addTool(
      name: 'kitchen.stats',
      description: 'How many times the queue was read, and how many times the '
          'kitchen was told it moved',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => CallToolResult(content: [
        TextContent(
            text: jsonEncode({'reads': _reads, 'told': _told, 'opens': _opens, 'dones': _dones})),
      ]),
    );

    server.addTool(
      name: 'kitchen.done',
      description: 'Mark the oldest unfinished ticket as done',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async {
        final open = _tickets.where((t) => !t.done).toList();
        if (open.isEmpty) {
          return CallToolResult(content: [TextContent(text: 'nothing to make')]);
        }
        _dones++;
        open.first.done = true;
        _told++;
        server.notifyResourceUpdated(_queueUri);
        return CallToolResult(
            content: [TextContent(text: 'ticket ${open.first.no} done')]);
      },
    );
  }

  /// Which pass this screen hangs over. A kitchen with two passes needs to
  /// know which one it is looking at.
  static const station = 'PASS 1 · hot line';

  String _queueJson() {
    final open = _tickets.where((t) => !t.done).toList();
    return jsonEncode({
      'rows': [
        for (final t in open)
          {
            'no': '#${t.no}',
            'item': t.item,
            // Position on the pass. Derived from the order of the list, never
            // stored: a ticket that remembered "you are third" would be wrong
            // the moment the one ahead of it is bumped.
            'place': open.indexOf(t) == 0 ? 'ON THE PASS' : 'waiting',
          },
      ],
      'station': station,
      'openCount': open.length,
      'madeCount': _tickets.where((t) => t.done).length,
      'headline': open.isEmpty ? 'all caught up' : '${open.length} to make',
      'nextLabel': open.isEmpty ? 'nothing on the pass' : '#${open.first.no} ${open.first.item}',
      // The rule a pass runs by, printed where the cook can see it.
      'passRule': 'Bump when it leaves the pass, not when it is plated',
    });
  }
}

/// `--http=<port>` serves over streamable HTTP so that more than one client can
/// share this one process (a screen in AppPlayer and a second party on the
/// side). Without it the server speaks stdio, which is what a launcher expects.
TransportConfig transportFor(List<String> args) {
  final http = args.firstWhere((a) => a.startsWith('--http='), orElse: () => '');
  if (http.isEmpty) return const TransportConfig.stdio();
  return TransportConfig.streamableHttp(
    host: 'localhost',
    port: int.parse(http.substring('--http='.length)),
    endpoint: '/mcp',
  );
}
