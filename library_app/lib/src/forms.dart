import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';

class EditForm extends StatefulWidget {
  final String title;
  final String saveLabel;
  final Map<String, String> initial, labels;
  final Set<String> integers, optional, disabled;
  final Future<void> Function(Map<String, String>) save;
  const EditForm({
    super.key,
    required this.title,
    required this.initial,
    required this.labels,
    required this.save,
    this.saveLabel = 'Lưu thay đổi',
    this.integers = const {},
    this.optional = const {},
    this.disabled = const {},
  });
  @override
  State<EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<EditForm> {
  final form = GlobalKey<FormState>();
  late final fields = widget.initial.map(
    (k, v) => MapEntry(k, TextEditingController(text: v)),
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(fields.map((k, v) => MapEntry(k, v.text.trim())));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 500,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              for (final entry in widget.labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: entry.key == 'status'
                      ? DropdownButtonFormField<String>(
                          initialValue: fields[entry.key]!.text,
                          decoration: InputDecoration(labelText: entry.value),
                          items: const [
                            DropdownMenuItem(
                              value: 'ACTIVE',
                              child: Text('Hoạt động'),
                            ),
                            DropdownMenuItem(
                              value: 'INACTIVE',
                              child: Text('Ngừng hoạt động'),
                            ),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => fields[entry.key]!.text = v!,
                        )
                      : TextFormField(
                          controller: fields[entry.key],
                          enabled:
                              !busy && !widget.disabled.contains(entry.key),
                          keyboardType: widget.integers.contains(entry.key)
                              ? TextInputType.number
                              : TextInputType.text,
                          decoration: InputDecoration(labelText: entry.value),
                          validator: (v) {
                            if (!widget.optional.contains(entry.key) &&
                                (v == null || v.trim().isEmpty)) {
                              return 'Vui lòng nhập thông tin.';
                            }
                            if (widget.integers.contains(entry.key) &&
                                int.tryParse(v ?? '') == null) {
                              return 'Vui lòng nhập số nguyên.';
                            }
                            return null;
                          },
                        ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? 'Đang lưu…' : widget.saveLabel),
      ),
    ],
  );
}

Future<bool?> bookEditor(BuildContext context, LibraryApi api, [Doc? book]) {
  final b = book;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EditForm(
      title: b == null ? 'Thêm đầu sách mới' : 'Chỉnh sửa sách',
      saveLabel: b == null ? 'Thêm sách' : 'Lưu thay đổi',
      initial: {
        'bookCode': b?['bookCode'] ?? '',
        'title': b?['title'] ?? '',
        'authors': (b?['authors'] as List? ?? []).join(', '),
        'category': b?['category'] ?? '',
        'publisher': b?['publisher']?['name'] ?? '',
        'year': '${b?['publishedYear'] ?? DateTime.now().year}',
        'publisherYear': '${b?['publisher']?['year'] ?? DateTime.now().year}',
        'total': '${b?['totalCopies'] ?? 1}',
        'available': '${b?['availableCopies'] ?? 1}',
        'status': b?['status'] ?? 'ACTIVE',
      },
      labels: const {
        'bookCode': 'Mã sách',
        'title': 'Tên sách',
        'authors': 'Tác giả (ngăn cách bằng dấu phẩy)',
        'category': 'Thể loại',
        'publisher': 'Nhà xuất bản',
        'year': 'Năm xuất bản',
        'publisherYear': 'Năm nhà xuất bản (publisher.year)',
        'total': 'Tổng số bản',
        'available': 'Số bản còn',
        'status': 'Trạng thái',
      },
      integers: const {'year', 'publisherYear', 'total', 'available'},
      disabled: b == null ? {} : {'bookCode'},
      save: (v) => api.save('books', {
        'bookCode': v['bookCode'],
        'title': v['title'],
        'authors': v['authors']!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'category': v['category'],
        'publisher': {
          'name': v['publisher'],
          'year': int.parse(v['publisherYear']!),
        },
        'publishedYear': int.parse(v['year']!),
        'totalCopies': int.parse(v['total']!),
        'availableCopies': int.parse(v['available']!),
        'status': v['status'],
      }, b?['bookCode']),
    ),
  );
}

Future<bool?> personEditor(
  BuildContext context,
  LibraryApi api,
  String collection, [
  Doc? person,
]) {
  final reader = collection == 'readers';
  final key = reader ? 'readerId' : 'staffId';
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EditForm(
      title:
          '${person == null ? 'Thêm' : 'Chỉnh sửa'} ${reader ? 'độc giả' : 'nhân viên'}',
      initial: {
        key: person?[key] ?? '',
        'fullName': person?['fullName'] ?? '',
        'email': person?['email'] ?? '',
        if (reader) ...{
          'phone': person?['phone'] ?? '',
          'address': person?['address'] ?? '',
        } else
          'role': person?['role'] ?? 'LIBRARIAN',
        'status': person?['status'] ?? 'ACTIVE',
      },
      labels: {
        key: reader ? 'Mã độc giả' : 'Mã nhân viên',
        'fullName': 'Họ tên',
        'email': 'Email',
        if (reader) ...{
          'phone': 'Số điện thoại',
          'address': 'Địa chỉ',
        } else
          'role': 'Vai trò',
        'status': 'Trạng thái',
      },
      disabled: person == null ? {} : {key},
      optional: const {'phone', 'address'},
      save: (v) => api.save(collection, v, person?[key]),
    ),
  );
}

class LoanForm extends StatefulWidget {
  final LibraryApi api;
  final List<Doc> books, readers, staff;
  final String? initialBook;
  const LoanForm({
    super.key,
    required this.api,
    required this.books,
    required this.readers,
    required this.staff,
    this.initialBook,
  });
  @override
  State<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends State<LoanForm> {
  String? reader, staff;
  late DateTime due = DateTime.now().add(const Duration(days: 14));
  late final List<Doc> lines = [
    {'bookCode': widget.initialBook, 'quantity': 1},
  ];
  bool busy = false;
  String? error;
  Future<void> submit() async {
    if (reader == null ||
        staff == null ||
        lines.any((l) => l['bookCode'] == null || l['quantity'] < 1)) {
      setState(
        () =>
            error = 'Chọn độc giả, nhân viên và sách; số lượng phải lớn hơn 0.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request('POST', 'loans', {
        'readerId': reader,
        'staffId': staff,
        'dueDate': due.toUtc().toIso8601String(),
        'items': lines,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  Widget person(
    String label,
    List<Doc> people,
    String key,
    String? selected,
    ValueChanged<String?> change,
  ) => DropdownButtonFormField<String>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: people
        .where((p) => p['status'] == 'ACTIVE')
        .map(
          (p) => DropdownMenuItem<String>(
            value: p[key],
            child: Text(
              '${p[key]} · ${p['fullName']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: busy ? null : change,
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Lập phiếu mượn'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            person(
              'Độc giả',
              widget.readers,
              'readerId',
              reader,
              (v) => setState(() => reader = v),
            ),
            const SizedBox(height: 16),
            person(
              'Nhân viên xử lý',
              widget.staff,
              'staffId',
              staff,
              (v) => setState(() => staff = v),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hạn trả'),
              subtitle: Text(day(due.toIso8601String())),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: busy
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final value = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: now.add(const Duration(days: 1)),
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (value != null && mounted) {
                        setState(
                          () => due = DateTime(
                            value.year,
                            value.month,
                            value.day,
                            23,
                            59,
                          ),
                        );
                      }
                    },
            ),
            const Divider(),
            for (int i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('book-$i-${lines[i]['bookCode']}'),
                      initialValue: lines[i]['bookCode'],
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Chọn sách'),
                      items: widget.books
                          .where(
                            (b) =>
                                b['status'] == 'ACTIVE' &&
                                b['availableCopies'] > 0,
                          )
                          .map(
                            (b) => DropdownMenuItem<String>(
                              value: b['bookCode'],
                              child: Text(
                                '${b['title']} · còn ${b['availableCopies']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => lines[i]['bookCode'] = v),
                    ),
                    Row(
                      children: [
                        const Text('Số lượng'),
                        IconButton(
                          onPressed: busy || lines[i]['quantity'] <= 1
                              ? null
                              : () => setState(() => lines[i]['quantity']--),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${lines[i]['quantity']}'),
                        IconButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => lines[i]['quantity']++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        const Spacer(),
                        if (lines.length > 1)
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => lines.removeAt(i)),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: busy || lines.length >= 30
                  ? null
                  : () => setState(
                      () => lines.add({'bookCode': null, 'quantity': 1}),
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Thêm sách vào phiếu'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? 'Đang tạo…' : 'Xác nhận mượn'),
      ),
    ],
  );
}

Future<bool?> returnEditor(BuildContext context, LibraryApi api, Doc loan) {
  final remaining = (loan['items'] as List)
      .where((i) => i['returnedQuantity'] < i['quantity'])
      .toList();
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EditForm(
      title: 'Trả sách · ${loan['loanCode']}',
      initial: {
        for (final i in remaining)
          i['bookCode']: '${i['quantity'] - i['returnedQuantity']}',
      },
      labels: {
        for (final i in remaining)
          i['bookCode']:
              '${i['title']} (còn ${i['quantity'] - i['returnedQuantity']})',
      },
      integers: remaining.map((i) => i['bookCode'] as String).toSet(),
      save: (v) async {
        if (v.values.any((q) => int.parse(q) < 0)) {
          throw ApiException(
            'Số trả không được âm. Nhập 0 nếu chưa trả sách đó.',
          );
        }
        await api.request('POST', 'loans/${loan['loanCode']}/return', {
          'items': [
            for (final entry in v.entries)
              if (int.parse(entry.value) > 0)
                {'bookCode': entry.key, 'quantity': int.parse(entry.value)},
          ],
        });
      },
    ),
  );
}
