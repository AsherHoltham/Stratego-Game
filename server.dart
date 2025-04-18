import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'dart:async';

class ChatLog {
  Map<String, String> mLog = {};
}

class GameData {
  List<TileType> mData = [];
  List<TileType> p1Data = [];
  List<TileType> p2Data = [];
  bool recBoardConfig1 = false;
  bool recBoardConfig2 = false;

  Completer<void> _bothDataCompleter = Completer<void>();
  GameData() {
    mData = List<TileType>.filled(100, TileType(0, 0), growable: false);
  }

  Future<void> waitForBothPlayers() => _bothDataCompleter.future;

  void mergeAndStartGame() {
    if (!_bothDataCompleter.isCompleted) {
      mData = List<TileType>.filled(100, TileType(0, 0), growable: false);

      int index = 0;
      for (int i = 0; i < 40; i++) {
        mData[index] = TileType(p2Data[i].pieceVal, p2Data[i].type);
        index++;
      }
      for (int i = 0; i < 20; i++) {
        mData[index] = TileType(p2Data[i + 40].pieceVal, p2Data[i + 40].type);
        index++;
      }
      for (int i = 0; i < 40; i++) {
        mData[index] = TileType(p1Data[i + 60].pieceVal, p1Data[i + 60].type);
        index++;
      }

      _bothDataCompleter.complete();
    }
  }
}

class TileType {
  int pieceVal;
  int type;
  TileType(this.pieceVal, this.type);

  Map<String, dynamic> toJson() {
    return {
      'pieceVal': pieceVal,
      'type': type,
    };
  }
}

Future<Response> chatController(Request request, ChatLog log) async {
  if (request.method == 'GET') {
    final responseBody = jsonEncode({
      'headers': 'chat',
      'context': log.mLog,
    });
    return Response.ok(responseBody,
        headers: {'Content-Type': 'application/json'});
  } else if (request.method == 'POST') {
    final payload = await request.readAsString();
    final Map<String, dynamic> data = jsonDecode(payload);
    log.mLog[data["message"]] = data["user"];
    return Response.ok('Received chat POST with payload: $payload');
  } else {
    return Response(405, body: 'Method not allowed');
  }
}

Future<Response> gameController(Request request, GameData gameData) async {
  if (request.method == 'GET') {
    await gameData.waitForBothPlayers();

    final responseBody = jsonEncode({
      'headers': 'game',
      'context': gameData.mData.map((tile) => tile.toJson()).toList(),
    });
    return Response.ok(responseBody,
        headers: {'Content-Type': 'application/json'});
  } else if (request.method == 'POST') {
    final payload = await request.readAsString();
    final Map<String, dynamic> fdata = jsonDecode(payload);
    final String playerID = fdata["user"];
    final List<dynamic> rawData = fdata["data"];
    final List<TileType> data = rawData.map<TileType>((tile) {
      return TileType(tile['pieceVal'] as int, tile['type'] as int);
    }).toList();
    if (playerID == 'Player1' && !gameData.recBoardConfig1) {
      print("p1");
      gameData.recBoardConfig1 = true;
      gameData.p1Data = data;
    } else if (playerID == 'Player2' && !gameData.recBoardConfig2) {
      print("p2");
      gameData.recBoardConfig2 = true;
      gameData.p2Data = data;
    } else {
      gameData.mData = data;
    }
    if (gameData.recBoardConfig1 && gameData.recBoardConfig2) {
      gameData.mergeAndStartGame();
    }
    await gameData.waitForBothPlayers();

    final responseData = {
      'message': 'data',
      'data': gameData.mData.asMap().map((key, tile) => MapEntry(
          key.toString(), {'pieceVal': tile.pieceVal, 'type': tile.type}))
    };

    return Response.ok(jsonEncode(responseData),
        headers: {'Content-Type': 'application/json'});
  } else {
    return Response(405, body: 'Method not allowed');
  }
}

void main(List<String> args) async {
  final chatLog = ChatLog();
  final gameData = GameData();
  final router = Router();

  router.get('/chat', (Request request) => chatController(request, chatLog));
  router.post('/chat', (Request request) => chatController(request, chatLog));
  router.get('/game', (Request request) => gameController(request, gameData));
  router.post('/game', (Request request) => gameController(request, gameData));

  var handler = Pipeline().addMiddleware(logRequests()).addHandler(router);

  final port = int.parse(Platform.environment['APP_PORT'] ?? '8080');
  final server = await io.serve(handler, '0.0.0.0', port);

  print('Server listening on port ${server.port}');
}
