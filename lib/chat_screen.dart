import 'package:flutter/material.dart';
import 'cloud_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String contactName;

  const ChatScreen({super.key, required this.contactName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  String _latestMessage = '';
  bool _iSentIt = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contactName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [

          // Bubble area
          Expanded(
            child: Center(
              child: _latestMessage.isEmpty
                  ? const Text(
                'No messages yet...',
                style: TextStyle(color: Colors.grey),
              )
                  : CloudBubble(
                message: _latestMessage,
                isSentByMe: _iSentIt,
              ),
            ),
          ),

          // Input area
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: const BorderSide(
                          color: Colors.deepPurple,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send as me button
                IconButton(
                  onPressed: () {
                    if (_messageController.text.trim().isEmpty) return;
                    setState(() {
                      _latestMessage = _messageController.text.trim();
                      _iSentIt = true;
                      _messageController.clear();
                    });
                  },
                  icon: const Icon(Icons.send, color: Colors.deepPurple),
                ),

                // Simulate reply button
                IconButton(
                  onPressed: () {
                    if (_messageController.text.trim().isEmpty) return;
                    setState(() {
                      _latestMessage = _messageController.text.trim();
                      _iSentIt = false;
                      _messageController.clear();
                    });
                  },
                  icon: const Icon(Icons.reply, color: Colors.grey),
                ),

              ],
            ),
          ),

        ],
      ),
    );
  }
}