import 'package:flutter/material.dart';

import 'api.dart';

const ink = Color(0xFF172D2A);
const forest = Color(0xFF245C4A);
const canvas = Color(0xFFF6F7F3);
const muted = Color(0xFF74817A);
const line = Color(0xFFE4E9E2);
const palette = [
  Color(0xFFDFC4A0),
  Color(0xFFBBD0C7),
  Color(0xFFC5C7DD),
  Color(0xFFDCAFA0),
  Color(0xFFD6D4A8),
  Color(0xFFAFCDD6),
];
String day(dynamic raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  return d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

bool overdue(Doc loan) =>
    loan['status'] != 'RETURNED' &&
    (DateTime.tryParse(loan['dueDate'].toString())?.isBefore(DateTime.now()) ??
        false);
String labelStatus(Doc loan) => loan['status'] == 'RETURNED'
    ? 'Đã trả'
    : overdue(loan)
    ? 'Quá hạn'
    : 'Đang mượn';

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class Pill extends StatelessWidget {
  final String label;
  final bool warning;
  const Pill(this.label, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFBE8DF) : const Color(0xFFEDF3EC),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: warning ? const Color(0xFF9E4932) : forest,
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const EmptyState(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.auto_stories_outlined, size: 45, color: muted),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    ),
  );
}

class BookCover extends StatelessWidget {
  final Doc book;
  final int index;
  final double height;
  const BookCover(this.book, this.index, {super.key, this.height = 164});
  @override
  Widget build(BuildContext context) {
    final hash = book['bookCode'].toString().codeUnits.fold(0, (a, b) => a + b);
    final bg = palette[hash % palette.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: bg)),
            Positioned(
              right: -30,
              bottom: -50,
              child: Transform.rotate(
                angle: -.4,
                child: Container(
                  width: 160,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(70),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: ink.withValues(alpha: .12)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 18, 18, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book['category'].toString().toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.3,
                      color: ink.withValues(alpha: .65),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        book['title'].toString(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 22,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, size: 17, color: ink),
                      const Spacer(),
                      Text(
                        book['publishedYear'].toString(),
                        style: const TextStyle(fontSize: 10, color: ink),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const SectionTitle(this.title, this.subtitle, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 13)),
          ],
        ),
        ?trailing,
      ],
    ),
  );
}
