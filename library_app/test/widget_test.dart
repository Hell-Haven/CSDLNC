import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/src/api.dart';
import 'package:library_app/src/app.dart';

void main() {
  late Doc data;
  late LibraryApi api;
  late List<Uri> requests;
  setUp(() {
    requests = [];
    data =
        jsonDecode(File('../server/data/seed.json').readAsStringSync()) as Doc;
    data['mode'] = 'demo';
    api = LibraryApi(
      client: MockClient((req) async {
        requests.add(req.url);
        Object result = req.method == 'GET' ? data : {'message': 'OK'};
        if (req.method == 'GET' && req.url.path == '/books') {
          final params = req.url.queryParameters;
          final q = params['q'] ?? '';
          final category = params['category'];
          final books = (data['books'] as List).cast<Doc>().where((book) {
            return (category == null || book['category'] == category) &&
                '${book['bookCode']} ${book['title']} ${book['authors']}'
                    .toLowerCase()
                    .contains(q.toLowerCase());
          }).toList();
          final sort = params['sort'] ?? 'title';
          final direction = params['order'] == 'desc' ? -1 : 1;
          books.sort((a, b) {
            final left = a[sort], right = b[sort];
            return (left is num
                    ? left.compareTo(right as num)
                    : left.toString().compareTo(right.toString())) *
                direction;
          });
          result = books;
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });
  tearDown(() => api.close());
  testWidgets('desktop navigation, catalog search and book details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(LibraryApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Chào mừng đến với Mộc'), findsOneWidget);
    await tester.tap(find.text('Sách').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'mongo');
    await tester.pumpAndSettle();
    expect(find.text('1 kết quả'), findsOneWidget);
    expect(requests.last.queryParameters['q'], 'mongo');
    await tester.tap(find.text('Cơ sở dữ liệu MongoDB').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Nhà xuất bản: NXB Giáo dục'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xóa tìm kiếm'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Văn học'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['category'], 'Văn học');
    expect(find.text('1 kết quả'), findsOneWidget);
    final sortField = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(sortField);
    await tester.tap(sortField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Năm xuất bản mới nhất').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['sort'], 'publishedYear');
    expect(requests.last.queryParameters['order'], 'desc');
    expect(requests.last.queryParameters['category'], 'Văn học');
    await tester.tap(find.text('Lập phiếu mượn').first);
    await tester.pumpAndSettle();
    expect(find.text('Chưa có phiếu mượn phù hợp'), findsOneWidget);
    await tester.tap(find.text('Quản trị').first);
    await tester.pumpAndSettle();
    expect(find.text('Võ Công Trí').first, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 320.0]) {
    testWidgets('mobile $width all four pages fit without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(LibraryApp(api: api));
      await tester.pumpAndSettle();
      for (final label in ['Sách', 'Lập phiếu mượn', 'Quản trị', 'Trang chủ']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('connection failures provide retry and recover', (tester) async {
    var fail = true;
    final client = MockClient((req) async {
      if (fail) throw const SocketException('offline');
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final failingApi = LibraryApi(client: client);
    addTearDown(failingApi.close);
    await tester.pumpWidget(LibraryApp(api: failingApi));
    await tester.pumpAndSettle();
    expect(find.text('Thử kết nối lại'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Thử kết nối lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chào mừng đến với Mộc'), findsOneWidget);
  });
  if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
    testWidgets('capture desktop and mobile previews', (tester) async {
      await tester.runAsync(() async {
        final textFonts = FontLoader('Roboto');
        for (final weight in ['Regular', 'Medium', 'Bold']) {
          textFonts.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
        }
        await textFonts.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory('../previews')..createSync(recursive: true);
      for (final size in [const Size(1440, 1100), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: LibraryApp(api: api),
          ),
        );
        await tester.pumpAndSettle();
        for (final page in ['Trang chủ', 'Sách', 'Lập phiếu mượn', 'Quản trị']) {
          if (size.width < 950) {
            await tester.tap(
              find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text(page),
              ),
            );
          } else {
            await tester.tap(find.text(page).first);
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final index = [
              'Trang chủ',
              'Sách',
              'Lập phiếu mượn',
              'Quản trị',
            ].indexOf(page);
            File('${directory.path}/${size.width.toInt()}-$index.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
