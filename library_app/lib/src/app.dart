import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';
import 'forms.dart';

class LibraryApp extends StatelessWidget {
  final LibraryApi? api;
  const LibraryApp({super.key, this.api});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mộc · Thư viện số',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: forest,
        primary: forest,
        surface: Colors.white,
      ),
      fontFamily: 'Roboto',
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAF6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line),
    ),
    home: LibraryShell(api: api),
  );
}

class LibraryShell extends StatefulWidget {
  final LibraryApi? api;
  const LibraryShell({super.key, this.api});
  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell> {
  late final api = widget.api ?? LibraryApi();
  Doc? data;
  bool loading = true;
  String? error;
  int tab = 0;
  String query = '',
      category = 'Tất cả',
      historyFilter = 'Tất cả',
      selectedReader = '';
  final search = TextEditingController();
  Timer? searchTimer;
  List<Doc> bookResults = [];
  String bookSort = 'title:asc';
  String? bookError;
  bool booksLoading = false;
  int bookRequest = 0;
  static const names = ['Trang chủ', 'Sách', 'Lập phiếu mượn', 'Quản trị'];
  static const icons = [
    Icons.grid_view_rounded,
    Icons.auto_stories_outlined,
    Icons.history_rounded,
    Icons.person_outline_rounded,
  ];
  List<Doc> records(String name) => (data?[name] as List? ?? []).cast<Doc>();
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    searchTimer?.cancel();
    search.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> refresh() async {
    searchTimer?.cancel();
    bookRequest++;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final next = await api.snapshot();
      if (mounted) {
        setState(() {
          data = next;
          bookResults = records('books');
          loading = false;
          if (!records('readers').any((r) => r['readerId'] == selectedReader)) {
            selectedReader = records('readers').firstOrNull?['readerId'] ?? '';
          }
        });
        if (tab == 1) await loadBooks();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.toString();
        });
      }
    }
  }

  void navigate(int value) {
    searchTimer?.cancel();
    bookRequest++;
    setState(() {
      tab = value;
      query = '';
      search.clear();
    });
    if (value == 1) loadBooks();
  }

  Future<void> loadBooks() async {
    searchTimer?.cancel();
    final request = ++bookRequest;
    setState(() {
      booksLoading = true;
      bookError = null;
    });
    try {
      final sort = bookSort.split(':');
      final results = await api.books(
        query: query,
        category: category == 'Tất cả' ? '' : category,
        sort: sort[0],
        order: sort[1],
      );
      if (!mounted || request != bookRequest) return;
      setState(() {
        bookResults = results;
        booksLoading = false;
      });
    } catch (e) {
      if (!mounted || request != bookRequest) return;
      setState(() {
        bookError = e.toString();
        booksLoading = false;
      });
    }
  }

  void changeSearch(String value) {
    setState(() => query = value.toLowerCase());
    if (tab == 1) {
      bookRequest++;
      searchTimer?.cancel();
      searchTimer = Timer(const Duration(milliseconds: 300), loadBooks);
    }
  }

  void toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> editBook([Doc? b]) async {
    if (await bookEditor(context, api, b) == true) {
      toast('Đã lưu sách.');
      await refresh();
    }
  }

  Future<void> editPerson(String type, [Doc? p]) async {
    if (await personEditor(context, api, type, p) == true) {
      toast('Đã lưu thông tin.');
      await refresh();
    }
  }

  Future<void> borrow([String? bookCode]) async {
    if (await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => LoanForm(
            api: api,
            books: records('books'),
            readers: records('readers'),
            staff: records('staff'),
            initialBook: bookCode,
          ),
        ) ==
        true) {
      toast('Đã lập phiếu mượn và cập nhật tồn kho.');
      await refresh();
    }
  }

  Future<void> remove(String collection, Doc doc) async {
    final key = {
      'books': 'bookCode',
      'readers': 'readerId',
      'staff': 'staffId',
    }[collection]!;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa bản ghi?'),
        content: Text(
          'Bạn muốn xóa ${doc[key]}? Bản ghi có lịch sử mượn sẽ được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await api.delete(collection, doc[key]);
      if (mounted) toast('Đã xóa bản ghi.');
      await refresh();
    } catch (e) {
      if (mounted) toast(e.toString());
    }
  }

  void details(Doc book) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(book['title']),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(book, 0, height: 200),
              const SizedBox(height: 20),
              Text(
                'Mã sách: ${book['bookCode']}\nTác giả: ${(book['authors'] as List).join(', ')}\n'
                'Thể loại: ${book['category']}\nNhà xuất bản: ${book['publisher']['name']}\n'
                'Năm xuất bản: ${book['publishedYear']}\nNăm nhà xuất bản: ${book['publisher']['year']}\n'
                'Số bản còn: ${book['availableCopies']}/${book['totalCopies']}\n'
                'Trạng thái: ${book['status'] == 'ACTIVE' ? 'Hoạt động' : 'Ngừng hoạt động'}',
                style: const TextStyle(height: 1.9),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 950;
      return Scaffold(
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: navigate,
                destinations: [
                  for (var i = 0; i < 4; i++)
                    NavigationDestination(
                      icon: Icon(icons[i]),
                      label: names[i],
                    ),
                ],
              ),
        body: Row(
          children: [
            if (wide) sidebar(),
            Expanded(
              child: Column(
                children: [
                  header(wide),
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey(tab),
                      padding: EdgeInsets.all(wide ? 34 : 18),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1400),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Surface(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          error!,
                                          style: const TextStyle(
                                            color: Colors.red,
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: refresh,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Thử kết nối lại'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (data == null && !loading)
                                const EmptyState(
                                  'Chưa kết nối được thư viện',
                                  'Khởi động API rồi chọn Thử kết nối lại.',
                                ),
                              if (data != null) ...[
                                if (data!['mode'] == 'demo')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 18),
                                    child: Row(
                                      children: [
                                        const Pill('Dữ liệu mẫu'),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Thay đổi được giữ đến khi khởi động lại API.',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: muted.withValues(
                                                alpha: .95,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                switch (tab) {
                                  0 => home(wide),
                                  1 => booksPage(),
                                  2 => historyPage(),
                                  _ => profilePage(),
                                },
                                const SizedBox(height: 28),
                                const Text(
                                  'MỘC  /  Không gian tri thức của bạn',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: muted,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget sidebar() => Container(
    width: 226,
    color: const Color(0xFF173D32),
    padding: const EdgeInsets.all(24),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.spa_outlined, color: Color(0xFFD7E5C7), size: 33),
              SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'mộc.',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Roboto',
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 9, bottom: 50),
            child: Text(
              'THƯ VIỆN SỐ',
              style: TextStyle(
                color: Color(0xFF9DBAA9),
                letterSpacing: 3,
                fontSize: 10,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 15, left: 12),
            child: Text(
              'KHÁM PHÁ',
              style: TextStyle(
                color: Color(0xFF91AF9F),
                fontSize: 9,
                letterSpacing: 1.6,
              ),
            ),
          ),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: tab == i ? const Color(0xFF315748) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(
                    icons[i],
                    color: tab == i
                        ? const Color(0xFFDCEACD)
                        : const Color(0xFFA2BBAE),
                    size: 21,
                  ),
                  title: Text(
                    names[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: tab == i ? Colors.white : const Color(0xFFB5CABE),
                      fontWeight: tab == i
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => navigate(i),
                ),
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF426553)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote, color: Color(0xFFB5C9A5)),
                SizedBox(height: 12),
                Text(
                  'Mỗi trang sách,\nmột điều mới.',
                  style: TextStyle(
                    color: Color(0xFFDFE8D8),
                    fontFamily: 'Roboto',
                    fontSize: 18,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'ĐỌC • HỌC • KHÁM PHÁ',
                  style: TextStyle(
                    color: Color(0xFF93AF9C),
                    fontSize: 8,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            data?['mode'] == 'atlas'
                ? '●  MongoDB Atlas'
                : data?['mode'] == 'sqlserver'
                ? '●  SQL Server'
                : '○  Không gian thực hành',
            style: const TextStyle(color: Color(0xFFA6C5AC), fontSize: 10),
          ),
        ],
      ),
    ),
  );
  Widget header(bool wide) => Container(
    padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 18, vertical: 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!wide) ...[
          const Icon(Icons.spa_outlined, color: forest),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            wide ? 'Thư viện  /  ${names[tab]}' : names[tab],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: 'Làm mới dữ liệu',
          onPressed: loading ? null : refresh,
          icon: const Icon(Icons.refresh, size: 20),
        ),
        if (wide) ...[
          const SizedBox(width: 12),
          Text(
            day(DateTime.now().toIso8601String()),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(width: 24),
        ],
        InkWell(
          onTap: () => navigate(3),
          borderRadius: BorderRadius.circular(30),
          child: const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFE5ECD9),
            child: Icon(Icons.person_outline, size: 20, color: forest),
          ),
        ),
      ],
    ),
  );

  Widget home(bool wide) {
    final books = records('books');
    final loans = records('loans');
    final total = books.fold<int>(0, (n, b) => n + (b['totalCopies'] as int));
    final available = books.fold<int>(
      0,
      (n, b) => n + (b['availableCopies'] as int),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Chào mừng đến với Mộc',
          'Một nơi để đọc, học và tìm thấy cảm hứng.',
        ),
        Container(
          padding: EdgeInsets.all(wide ? 34 : 24),
          decoration: BoxDecoration(
            color: const Color(0xFFDDE7D4),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MỞ SÁCH. MỞ TƯƠNG LAI.',
                      style: TextStyle(
                        fontSize: 10,
                        color: forest,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Một cuốn sách,\nmột thế giới mới.',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: wide ? 39 : 30,
                        height: 1.15,
                        color: const Color(0xFF214B37),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Khám phá bộ sưu tập và bắt đầu\nhành trình tri thức của riêng bạn.',
                      style: TextStyle(
                        color: Color(0xFF66795D),
                        height: 1.7,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => navigate(1),
                      icon: const Icon(Icons.arrow_forward, size: 17),
                      label: const Text('Khám phá sách'),
                    ),
                  ],
                ),
              ),
              if (wide)
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 245,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 205,
                          height: 205,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .35),
                          ),
                        ),
                        Transform.rotate(
                          angle: .17,
                          child: Container(
                            width: 130,
                            height: 192,
                            decoration: BoxDecoration(
                              color: const Color(0xFFB68567),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Transform.rotate(
                          angle: -.17,
                          child: Container(
                            width: 133,
                            height: 192,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF315E49),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: ink.withValues(alpha: .15),
                                  blurRadius: 18,
                                  offset: const Offset(8, 12),
                                ),
                              ],
                            ),
                            child: const Column(
                              children: [
                                SizedBox(height: 12),
                                Icon(
                                  Icons.spa_outlined,
                                  color: Color(0xFFD1D9AA),
                                  size: 42,
                                ),
                                SizedBox(height: 20),
                                Expanded(
                                  child: Center(
                                    child: FittedBox(
                                      child: Text(
                                        'The art\nof reading',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Roboto',
                                          color: Color(0xFFEAE6CB),
                                          fontSize: 22,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'MỘC LIBRARY',
                                  style: TextStyle(
                                    color: Color(0xFFB0C298),
                                    fontSize: 7,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (ctx, c) {
            final stats = [
              ('Đầu sách', '${books.length}', Icons.menu_book_outlined),
              ('Bản đang mượn', '${total - available}', Icons.bookmark_border),
              ('Độc giả', '${records('readers').length}', Icons.people_outline),
              (
                'Phiếu quá hạn',
                '${loans.where(overdue).length}',
                Icons.schedule,
              ),
            ];
            final columns = c.maxWidth > 650 ? 4 : 2;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final s in stats)
                  SizedBox(
                    width: (c.maxWidth - (columns - 1) * 14) / columns,
                    child: Surface(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(s.$3, size: 21, color: forest),
                          const SizedBox(height: 20),
                          Text(
                            s.$2,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.$1,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 32),
        SectionTitle(
          'Trên kệ sách',
          '$available / $total bản sẵn sàng cho hành trình mới.',
          trailing: TextButton.icon(
            onPressed: () => navigate(1),
            icon: const Icon(Icons.east, size: 16),
            label: const Text('Xem tất cả'),
          ),
        ),
        bookGrid(books.take(4).toList(), compact: true),
        const SizedBox(height: 30),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bộ sưu tập theo thể loại',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              if (books.isEmpty)
                const Text(
                  'Thêm sách để bắt đầu thống kê.',
                  style: TextStyle(color: muted),
                ),
              for (final entry in categoryCounts().entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${entry.value} đầu sách',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value:
                              entry.value / (books.isEmpty ? 1 : books.length),
                          minHeight: 6,
                          color: forest,
                          backgroundColor: canvas,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, int> categoryCounts() {
    if (data?['categories'] is List) {
      return {
        for (final row in data!['categories'])
          row['category'] as String: row['titles'] as int,
      };
    }
    final counts = <String, int>{};
    for (final b in records('books')) {
      counts.update(b['category'], (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Widget searchField(String hint) => TextField(
    controller: search,
    onChanged: changeSearch,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search, size: 20),
      suffixIcon: query.isEmpty
          ? null
          : IconButton(
              tooltip: 'Xóa tìm kiếm',
              onPressed: () {
                search.clear();
                changeSearch('');
              },
              icon: const Icon(Icons.close, size: 18),
            ),
    ),
  );
  Widget booksPage() {
    final books = bookResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Bộ sưu tập sách',
          '${records('books').length} đầu sách · Những câu chuyện đang chờ bạn.',
          trailing: FilledButton.icon(
            onPressed: () => editBook(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm sách'),
          ),
        ),
        searchField('Tìm tên sách, tác giả hoặc mã sách…'),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cat in ['Tất cả', ...categoryCounts().keys])
              ChoiceChip(
                label: Text(cat, style: const TextStyle(fontSize: 12)),
                selected: category == cat,
                onSelected: (_) {
                  setState(() => category = cat);
                  loadBooks();
                },
                showCheckmark: false,
                selectedColor: const Color(0xFFDDE8D7),
                side: const BorderSide(color: line),
              ),
          ],
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: bookSort,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sắp xếp',
            prefixIcon: Icon(Icons.sort),
          ),
          items: const [
            DropdownMenuItem(value: 'title:asc', child: Text('Tên sách A → Z')),
            DropdownMenuItem(
              value: 'title:desc',
              child: Text('Tên sách Z → A'),
            ),
            DropdownMenuItem(
              value: 'publishedYear:desc',
              child: Text('Năm xuất bản mới nhất'),
            ),
            DropdownMenuItem(
              value: 'publishedYear:asc',
              child: Text('Năm xuất bản cũ nhất'),
            ),
            DropdownMenuItem(
              value: 'availableCopies:desc',
              child: Text('Số bản còn nhiều nhất'),
            ),
            DropdownMenuItem(
              value: 'bookCode:asc',
              child: Text('Mã sách tăng dần'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => bookSort = value);
            loadBooks();
          },
        ),
        const SizedBox(height: 16),
        if (booksLoading) const LinearProgressIndicator(),
        if (bookError != null) ...[
          Text(bookError!, style: const TextStyle(color: Colors.red)),
          TextButton(
            onPressed: loadBooks,
            child: const Text('Thử tải sách lại'),
          ),
        ],
        Text(
          '${books.length} kết quả',
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 16),
        bookGrid(books),
      ],
    );
  }

  Widget bookGrid(List<Doc> books, {bool compact = false}) {
    if (books.isEmpty) {
      return const EmptyState(
        'Chưa có sách phù hợp',
        'Thử từ khóa khác hoặc thêm một đầu sách mới.',
      );
    }
    return LayoutBuilder(
      builder: (ctx, c) {
        final columns = c.maxWidth > 1080
            ? 4
            : c.maxWidth > 760
            ? 3
            : c.maxWidth > 480
            ? 2
            : 1;
        final width = (c.maxWidth - (columns - 1) * 18) / columns;
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            for (int i = 0; i < books.length; i++)
              SizedBox(
                width: width,
                child: Surface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => details(books[i]),
                        child: BookCover(books[i], i),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        height: 40,
                        child: Text(
                          books[i]['title'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        (books[i]['authors'] as List).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Pill(
                            books[i]['status'] == 'ACTIVE'
                                ? 'Còn ${books[i]['availableCopies']}/${books[i]['totalCopies']}'
                                : 'Ngừng hoạt động',
                            warning:
                                books[i]['availableCopies'] == 0 ||
                                books[i]['status'] != 'ACTIVE',
                          ),
                          Text(
                            books[i]['bookCode'],
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TextButton(
                              onPressed:
                                  books[i]['status'] != 'ACTIVE' ||
                                      books[i]['availableCopies'] == 0
                                  ? null
                                  : () => borrow(books[i]['bookCode']),
                              child: const Text(
                                'Mượn sách',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Sửa sách',
                              onPressed: () => editBook(books[i]),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                            ),
                            IconButton(
                              tooltip: 'Xóa sách',
                              onPressed: () => remove('books', books[i]),
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 17,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget historyPage() {
    final loans =
        records('loans')
            .where(
              (l) =>
                  (historyFilter == 'Tất cả' ||
                      labelStatus(l) == historyFilter) &&
                  '${l['loanCode']} ${l['readerId']} ${readerName(l['readerId'])} ${(l['items'] as List).map((i) => i['title']).join(' ')}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList()
          ..sort(
            (a, b) => b['borrowDate'].toString().compareTo(
              a['borrowDate'].toString(),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Lịch sử mượn trả',
          'Theo dõi từng cuốn sách, từ lúc mượn đến khi trở về.',
          trailing: FilledButton.icon(
            onPressed: () => borrow(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Lập phiếu mượn'),
          ),
        ),
        searchField('Tìm phiếu mượn, độc giả hoặc tên sách…'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in ['Tất cả', 'Đang mượn', 'Quá hạn', 'Đã trả'])
              ChoiceChip(
                label: Text(filter),
                selected: historyFilter == filter,
                onSelected: (_) => setState(() => historyFilter = filter),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (loans.isEmpty)
          const EmptyState(
            'Chưa có phiếu mượn phù hợp',
            'Lập phiếu mượn để bắt đầu ghi nhận lịch sử.',
          ),
        for (final loan in loans)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        loan['loanCode'],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Pill(labelStatus(loan), warning: overdue(loan)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${readerName(loan['readerId'])} · ${loan['readerId']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mượn ${day(loan['borrowDate'])}  →  Hạn trả ${day(loan['dueDate'])}  ·  ${loan['staffId']}',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                  const Divider(height: 28),
                  for (final item in loan['items'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.menu_book_outlined,
                            color: muted,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${item['title']} · ${item['bookCode']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${item['returnedQuantity']}/${item['quantity']} đã trả',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                  if (loan['status'] != 'RETURNED')
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (await returnEditor(context, api, loan) == true) {
                            toast('Đã ghi nhận trả sách.');
                            await refresh();
                          }
                        },
                        icon: const Icon(
                          Icons.assignment_return_outlined,
                          size: 17,
                        ),
                        label: const Text('Trả sách'),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String readerName(String id) =>
      records('readers')
          .where((r) => r['readerId'] == id)
          .firstOrNull?['fullName'] ??
      id;
  Widget profilePage() {
    final readers = records('readers');
    final person = readers
        .where((r) => r['readerId'] == selectedReader)
        .firstOrNull;
    final loans = records('loans')
        .where((l) => l['readerId'] == selectedReader)
        .toList();
    final outstanding = loans.fold<int>(
      0,
      (n, l) =>
          n +
          (l['items'] as List).fold<int>(
            0,
            (a, i) => a + ((i['quantity'] - i['returnedQuantity']) as int),
          ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Trang cá nhân',
          'Thông tin độc giả và hoạt động tại thư viện.',
        ),
        if (readers.isNotEmpty)
          SizedBox(
            width: 400,
            child: DropdownButtonFormField<String>(
              key: ValueKey(selectedReader),
              initialValue: selectedReader,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Chọn hồ sơ độc giả',
              ),
              items: readers
                  .map(
                    (r) => DropdownMenuItem<String>(
                      value: r['readerId'],
                      child: Text(
                        '${r['readerId']} · ${r['fullName']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => selectedReader = v!),
            ),
          ),
        const SizedBox(height: 20),
        if (person != null)
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: Color(0xFFE5ECD9),
                      child: Icon(
                        Icons.person_outline,
                        color: forest,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            person['fullName'],
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Thẻ thư viện ${person['readerId']}',
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '${person['email']}\n${person['phone']}\n${person['address']}',
                  style: const TextStyle(
                    height: 1.9,
                    color: muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Pill('${loans.length} phiếu mượn'),
                    Pill('$outstanding bản chưa trả'),
                    Pill(
                      person['status'] == 'ACTIVE'
                          ? 'Đang hoạt động'
                          : 'Ngừng hoạt động',
                      warning: person['status'] != 'ACTIVE',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => editPerson('readers', person),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('Sửa thông tin'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 32),
        peopleSection('readers', 'Quản lý độc giả'),
        const SizedBox(height: 28),
        peopleSection('staff', 'Quản lý nhân viên'),
      ],
    );
  }

  Widget peopleSection(String type, String title) {
    final key = type == 'readers' ? 'readerId' : 'staffId';
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton.icon(
                onPressed: () => editPerson(type),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Thêm mới'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (records(type).isEmpty)
            const Text('Chưa có dữ liệu.', style: TextStyle(color: muted)),
          for (final p in records(type))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['fullName'],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${p[key]} · ${p['email']}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          p['status'] == 'ACTIVE'
                              ? 'Hoạt động'
                              : 'Ngừng hoạt động',
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sửa thông tin',
                    onPressed: () => editPerson(type, p),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Xóa bản ghi',
                    onPressed: () => remove(type, p),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
