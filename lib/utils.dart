/// Central utility class for UniMap common logic
class UniUtils {
  /// Validates a Student/Staff ID based on the format "DC" + 4 digits (0000-0100)
  static String? validateStudentId(String id) {
    id = id.toUpperCase();
    if (!id.startsWith('DC')) {
      return 'Invalid ID';
    }
    if (id.length > 13) {
      return 'Invalid ID';
    }
    if (id.length < 6) {
      return 'Invalid ID';
    }

    // Extract potential last 4 digits (usually the end of the string)
    final lastFour = id.substring(id.length - 4);
    final numericValue = int.tryParse(lastFour);

    if (numericValue == null || !RegExp(r'^\d{4}$').hasMatch(lastFour)) {
      return 'Invalid ID';
    }

    if (numericValue < 0 || numericValue > 100) {
      return 'Invalid ID';
    }

    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) {
      return 'Invalid ID';
    }

    return null;
  }

  /// Capitalizes the first letter of each word
  static String toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
