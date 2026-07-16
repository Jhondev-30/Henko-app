import 'package:intl/intl.dart';

/// Formateo de moneda (USD por defecto).
class CurrencyFormatter {
  static final _fmt = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );

  static String format(num value) => _fmt.format(value);
}
