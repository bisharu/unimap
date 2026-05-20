/*
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/map_config.dart';

class GeminiService {
  GenerativeModel? _model;
  ChatSession? _chatSession;

  // Track if we have a valid API key setup
  bool get hasValidApiKey {
    return MapConfig.geminiApiKey.isNotEmpty && 
           MapConfig.geminiApiKey != 'YOUR_GEMINI_API_KEY';
  }

  void _initialize() {
    if (_model != null) return;

    final apiKey = MapConfig.geminiApiKey;
    if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY') {
      return;
    }

    // Comprehensive context about ADBU Engineering block to act as a hyper-local campus guide
    const systemInstructionText = '''
You are UniMap AI, a helpful, warm, and highly intelligent local campus guide for the Assam Don Bosco University (ADBU) Engineering & Technology block. Your goal is to guide students, faculty, and guests, and help them find rooms, labs, washrooms, and staff cabins.

Here is the exact map layout of the ADBU campus block:

---
GROUND FLOOR (Floor 0):
- Central Library: The main academic library.
- Cafeteria: The campus food court, canteen, and seating area.
- Washrooms: Accessible toilet facilities.
- Faculty Cabins (Ground Floor):
  * Room 117: Dr. Pranab Das (Associate Professor & HOD, Dept. of Computer Science & Engineering)
  * Room 118: Prof. Sonia Sharma (Assistant Professor, Dept. of Computer Science & Engineering)
  * Room 119: Dr. Amit Barua (Associate Professor, Dept. of Electrical & Electronics)
  * Room 120: Prof. Sonia Sen (Assistant Professor, Dept. of Electronics & Communications)
  * Room 121: Dr. Manas Jyoti (Professor, Dept. of Civil Engineering)
  * Room 122: Prof. Rishabh Dev (Assistant Professor, Dept. of Information Technology)

---
FIRST FLOOR (Floor 1):
- Lecture Classrooms
- Electrical & Electronics Labs
- Physics & Chemistry Labs
- Washrooms

---
SECOND FLOOR (Floor 2):
- Computer Labs (Lab 1, Lab 2, Lab 3): Primary programming and IT labs.
- Faculty Cabins (Second Floor):
  * Room 217: Dr. Bobby Sharma (Associate Professor, Dept. of Computer Science & Engineering)
  * Room 218: Prof. Gyani Sharma (Assistant Professor, Dept. of Computer Applications)
  * Room 219: Prof. Vijay Prasad (Assistant Professor, Dept. of Computer Applications)
  * Room 220: Dr. Smriti Priya (Professor, Dept. of Civil Engineering)
  * Room 221: Prof. Hemant Kalita (Assistant Professor, Dept. of Civil Engineering)
- Washrooms

---
THIRD FLOOR (Floor 3):
- Faculty Cabins (Third Floor):
  * Room 317: Dr. Bikramjit Goswami (Associate Professor, Dept. of Electrical & Electronics)
  * Room 318: Prof. P. Joseph (Assistant Professor, Dept. of Electrical & Electronics)
  * Room 319: Dr. Sunandan Baruah (Professor & Dean, Dept. of Engineering & Technology)
  * Room 320: Prof. Nupur Choudhury (Assistant Professor, Dept. of Electronics & Communications)
  * Room 321: Dr. Shakuntala Laskar (Professor, Dept. of Electronics & Communications)
  * Room 322: Prof. Gitanjali Devi (Assistant Professor, Dept. of Humanities & Social Sciences)
  * Room 324: Dr. Monmayuri Goswami (Associate Professor, Dept. of Basic Sciences)
  * Room 325: Prof. Subra Mukherjee (Assistant Professor, Dept. of Basic Sciences)
- Washrooms

---
FOURTH FLOOR (Floor 4):
- Research & Project Labs
- Conference Rooms & Seminar Halls
- Washrooms
---

GUIDELINES FOR RESPONDING:
1. Be polite, friendly, and enthusiastic. Feel free to use relevant emojis!
2. If the user asks where a particular room, faculty cabin, library, or lab is, ALWAYS mention the room name, room number, and floor explicitly (e.g., "Room 216 on the Second Floor"). This is crucial so that the app's visual parser can detect it and show a "Locate on Map" action button!
3. If you do not know the location of a specific person or resource, suggest they ask at the main desk, but be positive.
4. Keep answers relatively concise and easy to read on a mobile screen. Use bullet points or bold text where appropriate.
''';

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(systemInstructionText),
    );

    // Initialize an empty chat session
    _chatSession = _model!.startChat();
  }

  /// Sends a message to the chat session and returns the AI's response text.
  /// If the API key is not setup, returns a helpful message instructing the user to configure it.
  Future<String> sendMessage(String text) async {
    if (!hasValidApiKey) {
      return "⚠️ **Gemini API Key is not configured yet!**\n\nTo talk to me, please open `lib/config/map_config.dart` and paste your Gemini API key in `geminiApiKey`. You can get a free key from [Google AI Studio](https://aistudio.google.com/).";
    }

    _initialize();

    if (_chatSession == null) {
      return "Error: Could not initialize Gemini chat session.";
    }

    try {
      final response = await _chatSession!.sendMessage(Content.text(text));
      return response.text ?? "I couldn't generate a response. Please try again.";
    } catch (e) {
      return "❌ **API Connection Error:**\n\n${e.toString()}\n\nMake sure your API key is valid and you have an active internet connection.";
    }
  }

  /// Reset the ongoing chat conversation to start fresh
  void resetChat() {
    _chatSession = null;
    _model = null;
}
*/
