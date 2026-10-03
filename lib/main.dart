import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const PocketAIApp());
}

class PocketAIApp extends StatelessWidget {
  const PocketAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Edge LLM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB1D8B7)),
      ),
      home: const BentoHomeScreen(),
    );
  }
}

class BentoHomeScreen extends StatefulWidget {
  const BentoHomeScreen({super.key});

  @override
  State<BentoHomeScreen> createState() => _BentoHomeScreenState();
}

class _BentoHomeScreenState extends State<BentoHomeScreen> {
  static const platform = MethodChannel('com.pocketai/llama');
  
  bool _isModelLoaded = false;
  bool _isLoading = false;
  String _statusMessage = "Engine off";
  int _threadCount = 4; // Default to 4 threads

  // Load the model
  Future<void> _loadEngine() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Loading 531MB model with $_threadCount threads...";
    });
    
    try {
      final String result = await platform.invokeMethod('loadModel', {
        'path': '/sdcard/Download/pocket-ai-expense-q4.gguf',
        'threads': _threadCount
      });
      setState(() {
        _isModelLoaded = true;
        _statusMessage = "Engine Ready";
      });
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = "Error: \${e.message}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openExpenseChat() {
    if (!_isModelLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please start the AI Engine first!')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExpenseChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.blueAccent,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Hello Boss 👋",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        )
                      ]
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.power_settings_new),
                      color: _isModelLoaded ? Colors.green : Colors.grey,
                      onPressed: _isLoading ? null : _loadEngine,
                    ),
                  )
                ],
              ),
              const SizedBox(height: 32),
              
              // Big Title
              Text(
                "How can I help\nyou today?",
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                  height: 1.2,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Bento Box Grid
              Expanded(
                child: Row(
                  children: [
                    // Large Left Card
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onTap: _openExpenseChat,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFC7F000), // Lime Green
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.4),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.receipt_long, color: Colors.black87),
                              ),
                              const Text(
                                "Log\nExpense",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right Column (Two Cards)
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          // Top Right Card
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4C4FB), // Soft Purple
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.4),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.chat_bubble_outline, size: 20),
                                  ),
                                  const Text(
                                    "Chat with AI",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Bottom Right Card
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD1D9), // Soft Pink
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.4),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt_outlined, size: 20),
                                  ),
                                  const Text(
                                    "Scan Receipt",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Status / Engine State
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ]
                ),
                child: Row(
                  children: [
                    if (_isLoading) 
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    if (!_isLoading)
                      Icon(Icons.memory, color: _isModelLoaded ? Colors.green : Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    if (!_isModelLoaded && !_isLoading)
                      DropdownButton<int>(
                        value: _threadCount,
                        items: [1, 2, 4, 6, 8].map((int value) {
                          return DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value cores'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _threadCount = value;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// Screen 2: The Chat Interface for Logging an Expense
// ---------------------------------------------------------
class ExpenseChatScreen extends StatefulWidget {
  const ExpenseChatScreen({super.key});

  @override
  State<ExpenseChatScreen> createState() => _ExpenseChatScreenState();
}

class _ExpenseChatScreenState extends State<ExpenseChatScreen> {
  static const platform = MethodChannel('com.pocketai/llama');
  final TextEditingController _controller = TextEditingController();
  
  List<Map<String, String>> messages = [];
  bool _isGenerating = false;

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add({"role": "user", "content": text});
      _isGenerating = true;
    });
    _controller.clear();

    // The prompt format matching what we trained our LoRA on
    final prompt = "<|user|>\nExtract expenses to JSON: \$text\n<|model|>\n";

    try {
      final String response = await platform.invokeMethod('promptModel', {
        'prompt': prompt
      });
      
      setState(() {
        messages.add({"role": "ai", "content": response});
      });
    } on PlatformException catch (e) {
      setState(() {
        messages.add({"role": "ai", "content": "Error: \${e.message}"});
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Log Expense", 
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isUser = msg["role"] == "user";
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFFC7F000) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        )
                      ]
                    ),
                    child: Text(
                      msg["content"] ?? "",
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isGenerating)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Thinking...", style: TextStyle(color: Colors.grey)),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ]
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "E.g., Spent ₹500 on pizza today",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, color: Colors.white),
                    onPressed: _isGenerating ? null : _sendMessage,
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
