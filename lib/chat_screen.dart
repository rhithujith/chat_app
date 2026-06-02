import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cloud_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String contactName;
  final String contactPhone;
  final String contactUid;

  const ChatScreen({
    super.key,
    required this.contactName,
    required this.contactPhone,
    required this.contactUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  late final String currentUid;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    currentUid = currentUser?.uid ?? 'bypass_user';
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String getChatId() {
    return currentUid.compareTo(widget.contactUid) < 0
        ? '${currentUid}_${widget.contactUid}'
        : '${widget.contactUid}_$currentUid';
  }

  Future<void> _sendMessage({required bool simulateReply}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    final String sender = simulateReply ? widget.contactUid : currentUid;
    final String chatId = getChatId();

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'text': text,
        'senderId': sender,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update the main chat document for quick access query metadata
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'lastMessage': text,
        'lastActivity': FieldValue.serverTimestamp(),
        'users': [currentUid, widget.contactUid],
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  QueryDocumentSnapshot? _findLatestMessageForSender(
    List<QueryDocumentSnapshot> messages,
    String senderId,
  ) {
    for (final doc in messages) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['senderId'] == senderId) {
        return doc;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String chatId = getChatId();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contactName, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              widget.contactPhone,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Bubble stream area
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.deepPurple));
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final myLatest = _findLatestMessageForSender(messages, currentUid);
                final contactLatest = _findLatestMessageForSender(messages, widget.contactUid);

                final List<QueryDocumentSnapshot> displayMessages = [];
                if (myLatest != null) displayMessages.add(myLatest);
                if (contactLatest != null) displayMessages.add(contactLatest);

                // Sort chronologically (oldest first)
                displayMessages.sort((a, b) {
                  final aTime = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                  final bTime = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return aTime.compareTo(bTime);
                });

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 20),
                  itemCount: displayMessages.length,
                  itemBuilder: (context, index) {
                    final msgDoc = displayMessages[index];
                    final data = msgDoc.data() as Map<String, dynamic>;
                    final String text = data['text'] ?? '';
                    final String senderId = data['senderId'] ?? '';
                    final bool isSentByMe = senderId == currentUid;

                    return CloudBubble(
                      message: text,
                      isSentByMe: isSentByMe,
                    );
                  },
                );
              },
            ),
          ),

          // Input area
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 20, top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
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
                  onPressed: () => _sendMessage(simulateReply: false),
                  icon: const Icon(Icons.send, color: Colors.deepPurple),
                ),
                // Simulate reply button (Developer helper)
                IconButton(
                  onPressed: () => _sendMessage(simulateReply: true),
                  icon: const Icon(Icons.reply, color: Colors.grey),
                  tooltip: 'Simulate contact reply (Dev Only)',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}