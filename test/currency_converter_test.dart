import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/widgets/itzy/quickmenu/button_currency_converter.dart';

void main() {
  final Map<String, String> currencies = <String, String>{
    'usd': 'United States Dollar',
    'eur': 'Euro',
    'inr': 'Indian Rupee',
  };
  final Map<String, String> aliases = CurrencyConverterService.buildCurrencyAliases(currencies);

  ParsedConversionInput parse(String input, {String? defaultTargetCurrency}) {
    return CurrencyConverterService.parseConversionInput(
      input,
      currencies: currencies,
      aliases: aliases,
      defaultTargetCurrency: defaultTargetCurrency,
    );
  }

  group('CurrencyConverterService currency symbols', () {
    test('parses the Indian rupee symbol with Indian digit grouping', () {
      final ParsedConversionInput result = parse('₹10,342 to usd');

      expect(result.query?.amount, 10342);
      expect(result.query?.fromCurrency, 'inr');
      expect(result.query?.toCurrency, 'usd');
    });

    test('supports symbols with a space and symbols after the amount', () {
      final ParsedConversionInput prefixed = parse('₹ 10,342 to USD');
      final ParsedConversionInput suffixed = parse('10,342 ₹ to USD');

      expect(prefixed.query?.amount, 10342);
      expect(prefixed.query?.fromCurrency, 'inr');
      expect(suffixed.query?.amount, 10342);
      expect(suffixed.query?.fromCurrency, 'inr');
    });

    test('supports currency names and a default target with symbols', () {
      final ParsedConversionInput result = parse('₹10,342', defaultTargetCurrency: 'usd');
      final ParsedConversionInput named = parse('10,342 rupee to €');

      expect(result.query?.amount, 10342);
      expect(result.query?.fromCurrency, 'inr');
      expect(result.query?.toCurrency, 'usd');
      expect(named.query?.amount, 10342);
      expect(named.query?.fromCurrency, 'inr');
      expect(named.query?.toCurrency, 'eur');
    });

    test('keeps decimal separators distinct from thousands separators', () {
      final ParsedConversionInput result = parse('₹10.342,50 to EUR');

      expect(result.query?.amount, 10342.5);
      expect(result.query?.fromCurrency, 'inr');
      expect(result.query?.toCurrency, 'eur');
    });
  });
}
