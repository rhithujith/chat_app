import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'cloud_bubble.dart';
import 'notification_service.dart';

enum PickerAction { gallery, camera, simulateGallery }

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
  bool _isUploading = false;

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

      if (simulateReply) {
        await NotificationService.instance.showLocalNotification(
          title: widget.contactName,
          body: text,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    
    final PickerAction? action = await showModalBottomSheet<PickerAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Select Image Option',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.deepPurple),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, PickerAction.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.deepPurple),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, PickerAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.grey),
                title: const Text('Simulate Contact Reply (Gallery)'),
                onTap: () => Navigator.pop(context, PickerAction.simulateGallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (action == null) return;

    final ImageSource source = (action == PickerAction.camera) ? ImageSource.camera : ImageSource.gallery;
    final bool simulateReply = (action == PickerAction.simulateGallery);

    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final String chatId = getChatId();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('chat_images')
          .child(chatId)
          .child(fileName);

      final file = File(pickedFile.path);
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final String sender = simulateReply ? widget.contactUid : currentUid;

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'text': '',
        'imageUrl': downloadUrl,
        'senderId': sender,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'lastMessage': '📷 Sent an image',
        'lastActivity': FieldValue.serverTimestamp(),
        'users': [currentUid, widget.contactUid],
      }, SetOptions(merge: true));

      if (simulateReply) {
        await NotificationService.instance.showLocalNotification(
          title: widget.contactName,
          body: '📷 Sent an image',
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload/send image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
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
          if (_isUploading)
            const LinearProgressIndicator(color: Colors.deepPurple),
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
                    final String? imageUrl = data['imageUrl'];
                    final String senderId = data['senderId'] ?? '';
                    final bool isSentByMe = senderId == currentUid;

                    return CloudBubble(
                      message: text,
                      imageUrl: imageUrl,
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
                IconButton(
                  onPressed: _pickAndSendImage,
                  icon: const Icon(Icons.image, color: Colors.deepPurple),
                  tooltip: 'Send Image',
                ),
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