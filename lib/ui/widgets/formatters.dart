import 'package:intl/intl.dart';

final _euro = NumberFormat.currency(locale: 'it_IT', symbol: '€');
final _date = DateFormat('dd/MM/yyyy HH:mm', 'it_IT');
final _dateShort = DateFormat('dd/MM/yyyy', 'it_IT');

String euro(double v) => _euro.format(v);

String dateTime(int millis) =>
    _date.format(DateTime.fromMillisecondsSinceEpoch(millis));

String dateShort(int millis) =>
    _dateShort.format(DateTime.fromMillisecondsSinceEpoch(millis));
