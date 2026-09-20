import 'package:aim_cli/src/utils/validators.dart';
import 'package:test/test.dart';

void main() {
  group('FirebaseProjectIdValidator', () {
    test('accepts a valid id', () {
      expect(FirebaseProjectIdValidator.isValid('my-real-project'), isTrue);
    });

    test('rejects an id with spaces and uppercase letters', () {
      expect(FirebaseProjectIdValidator.isValid('My Project'), isFalse);
    });

    test('rejects an id containing a quote', () {
      // A quote would break the JSON `.firebaserc` interpolates it into.
      expect(FirebaseProjectIdValidator.isValid('a"b'), isFalse);
    });

    test('rejects an id shorter than 6 characters', () {
      expect(FirebaseProjectIdValidator.isValid('abcde'), isFalse);
    });

    test('accepts an id at the 30-character limit', () {
      expect(FirebaseProjectIdValidator.isValid('a${'b' * 29}'), isTrue);
    });

    test('rejects an id longer than 30 characters', () {
      expect(FirebaseProjectIdValidator.isValid('a${'b' * 30}'), isFalse);
    });

    test('rejects an id starting with a digit or hyphen', () {
      expect(FirebaseProjectIdValidator.isValid('1abcde'), isFalse);
      expect(FirebaseProjectIdValidator.isValid('-abcde'), isFalse);
    });

    test('rejects an id ending with a hyphen', () {
      expect(FirebaseProjectIdValidator.isValid('abcde-'), isFalse);
    });

    test('error message names the rule', () {
      final message = FirebaseProjectIdValidator.getErrorMessage('My Project');
      expect(message, contains('My Project'));
      expect(message, contains('lowercase'));
    });
  });
}
