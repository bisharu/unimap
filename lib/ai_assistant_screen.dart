/*
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/gemini_service.dart';
import 'homescreen.dart'; // Imports RoomSearchItem

class AIAssistantScreen extends StatefulWidget {
  final List<RoomSearchItem> allRooms;

  const AIAssistantScreen({super.key, required this.allRooms});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GeminiService _geminiService = GeminiService();
  bool _isLoading = false;

  final List<String> _suggestions = [
    "Where is HOD CSE?",
    "Find Dr. Bobby Sharma",
    "Where is Central Library?",
    "Find a computer lab",
    "Washrooms on Floor 3"
  ];

  @override
  void initState() {
    super.initState();
    // Add welcome message from UniMap AI
    _messages.add(ChatMessage(
      text: "👋 **Hello! I'm UniMap AI, your personal ADBU Campus Guide.**\n\nHow can I help you find your way around the campus today? Feel free to ask about classrooms, labs, HOD cabins, or faculty members!",
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage([String? customText]) async {
    final text = customText ?? _inputController.text.trim();
    if (text.isEmpty) return;

    if (customText == null) {
      _inputController.clear();
    }

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    // Call Gemini
    final aiResponse = await _geminiService.sendMessage(text);

    // Identify deep-link room from response
    final matchedRoom = _findMatchedRoom(text + " " + aiResponse);

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(
          text: aiResponse,
          isUser: false,
          matchedRoom: matchedRoom,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  RoomSearchItem? _findMatchedRoom(String text) {
    final cleanText = text.toLowerCase();

    for (final room in widget.allRooms) {
      final nameLower = room.name.toLowerCase();
      final typeLower = room.type.toLowerCase();
      final noLower = room.roomNo.toLowerCase();

      // Skip very generic or short room identifiers
      if (nameLower.length < 3) continue;

      // 1. Match exact room number (e.g. "Room 216" or "Cabin 117")
      if (noLower.isNotEmpty && noLower != 'null') {
        if (cleanText.contains(" $noLower") || 
            cleanText.contains("room $noLower") || 
            cleanText.contains("cabin $noLower") ||
            cleanText.contains("rm $noLower") ||
            cleanText.contains("rm. $noLower")) {
          return room;
        }
      }

      // 2. Match exact room name (e.g. "Library", "Cafeteria")
      if (cleanText.contains(nameLower)) {
        return room;
      }

      // 3. Match Faculty names (e.g. "Pranab Das" matches "Dr. Pranab Das")
      if (nameLower.contains("dr. ") || nameLower.contains("prof. ")) {
        final nameWithoutTitle = nameLower
            .replaceAll("dr. ", "")
            .replaceAll("prof. ", "")
            .trim();
        if (nameWithoutTitle.isNotEmpty && cleanText.contains(nameWithoutTitle)) {
          return room;
        }
      }

      // 4. Match key categories like "canteen", "restroom", "toilet"
      if (typeLower == 'toilet' || nameLower.contains('toilet') || nameLower.contains('washroom')) {
        if (cleanText.contains('toilet') || cleanText.contains('washroom') || cleanText.contains('restroom')) {
          if (cleanText.contains('ground') && room.floor == 0) return room;
          if ((cleanText.contains('first') || cleanText.contains('floor 1') || cleanText.contains('1st')) && room.floor == 1) return room;
          if ((cleanText.contains('second') || cleanText.contains('floor 2') || cleanText.contains('2nd')) && room.floor == 2) return room;
          if ((cleanText.contains('third') || cleanText.contains('floor 3') || cleanText.contains('3rd')) && room.floor == 3) return room;
          if ((cleanText.contains('fourth') || cleanText.contains('floor 4') || cleanText.contains('4th')) && room.floor == 4) return room;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium slate-900 dark theme
      body: Stack(
        children: [
          // ── Beautiful dynamic gradient background elements ──
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4F46E5).withOpacity(0.15), // Deep purple glow
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF06B6D4).withOpacity(0.15), // Cyan/teal glow
              ),
            ),
          ),

          // ── Main Page Content ──
          SafeArea(
            child: Column(
              children: [
                // ── App Bar Header ──
                _buildHeader(context),

                // ── Conversation Area ──
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _buildMessageBubble(msg);
                    },
                  ),
                ),

                // ── Thinking / Loading Indicator ──
                if (_isLoading) _buildThinkingIndicator(),

                // ── Floating Suggestions ──
                if (!_isLoading) _buildSuggestionsList(),

                // ── Input Field Bar ──
                _buildInputBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.3),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          // Logo/Avatar
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "UniMap Campus AI",
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Powered by Google Gemini 2.5 Flash",
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    color: Colors.cyanAccent.withOpacity(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: "Reset conversation",
            onPressed: () {
              setState(() {
                _geminiService.resetChat();
                _messages.clear();
                _messages.add(ChatMessage(
                  text: "👋 **Conversation reset! I'm ready for fresh questions.**\n\nHow can I help you navigate the ADBU campus today?",
                  isUser: false,
                ));
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("Chat conversation started fresh"),
                  backgroundColor: const Color(0xFF1E293B),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF4F46E5) // Sleek indigo for user prompts
              : const Color(0xFF1E293B).withOpacity(0.7), // Glassmorphism slate card
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(
            color: isUser 
                ? const Color(0xFF6366F1).withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rich markdown formatted text
            _renderMarkdownText(msg.text, isUser),
            
            // Locater deep link button
            if (msg.matchedRoom != null) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Return the matched room back to homescreen for focus and routing
                    Navigator.pop(context, msg.matchedRoom);
                  },
                  icon: const Icon(Icons.location_on_rounded, size: 16, color: Colors.white),
                  label: Text(
                    "Show ${msg.matchedRoom!.name} on Map",
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4), // Cyan neon theme
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _renderMarkdownText(String text, bool isUser) {
    // Simple custom parser for markdown elements like bold (`**`), headers, etc.
    final List<Widget> children = [];
    final List<String> paragraphs = text.split("\n");

    for (var p in paragraphs) {
      if (p.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }

      final List<TextSpan> spans = [];
      final boldRegex = RegExp(r'\*\*(.*?)\*\*');
      int lastIndex = 0;

      for (var match in boldRegex.allMatches(p)) {
        // Pre-match text
        if (match.start > lastIndex) {
          spans.add(TextSpan(text: p.substring(lastIndex, match.start)));
        }
        // Bold match text
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ));
        lastIndex = match.end;
      }

      if (lastIndex < p.length) {
        spans.add(TextSpan(text: p.substring(lastIndex)));
      }

      // Check if it's a list item
      bool isListItem = p.trim().startsWith('- ') || p.trim().startsWith('* ');
      final Widget pWidget = RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'googlesans',
            color: isUser ? Colors.white : const Color(0xFFE2E8F0),
            fontSize: 14,
            height: 1.4,
          ),
          children: spans,
        ),
      );

      if (isListItem) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "• ",
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.cyanAccent, 
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Expanded(child: pWidget),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: pWidget,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildThinkingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(left: 16, bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              color: Colors.cyanAccent,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "UniMap AI is thinking...",
            style: TextStyle(
              fontFamily: 'googlesans',
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final s = _suggestions[index];
          return GestureDetector(
            onTap: () {
              _handleSendMessage(s);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Center(
                child: Text(
                  s,
                  style: const TextStyle(
                    fontFamily: 'googlesans',
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _inputController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: Colors.cyanAccent,
                decoration: InputDecoration(
                  hintText: "Ask Campus Assistant...",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _handleSendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _handleSendMessage(),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final RoomSearchItem? matchedRoom;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.matchedRoom,
}
*/
