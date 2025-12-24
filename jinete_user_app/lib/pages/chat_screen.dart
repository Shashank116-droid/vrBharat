import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete/methods/common_methods.dart';

class ChatScreen extends StatefulWidget {
  final String rideRequestId;
  final String otherUserName; // Driver's name

  const ChatScreen({
    super.key,
    required this.rideRequestId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController textEditingController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  CommonMethods cMethods = CommonMethods();

  @override
  void dispose() {
    textEditingController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void sendMessage() {
    if (textEditingController.text.trim().isEmpty) return;

    String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    String messageText = textEditingController.text.trim();

    FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.rideRequestId)
        .collection('messages')
        .add({
      'text': messageText,
      'senderId': currentUserId,
      'senderName': "Rider", // Could be dynamic if we had User Model handy
      'timestamp': FieldValue.serverTimestamp(),
    });

    textEditingController.clear();

    // Auto-scroll to bottom
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0, // Reversed list, 0 is bottom
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // App Theme
      appBar: AppBar(
        title: Text(
          "Chat with ${widget.otherUserName}",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.rideRequestId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      "No messages yet.",
                      style: GoogleFonts.poppins(color: Colors.white54),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;
                final currentUser = FirebaseAuth.instance.currentUser;

                return ListView.builder(
                  controller: scrollController,
                  reverse:
                      true, // Show newest at bottom (requires descending sort)
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var data = messages[index].data() as Map<String, dynamic>;
                    bool isMe = data['senderId'] == currentUser?.uid;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 5, horizontal: 10),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFFFF6B00) // Accent Color
                              : const Color(0xFF181820), // Card Color
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isMe
                                ? const Radius.circular(12)
                                : const Radius.circular(0),
                            bottomRight: isMe
                                ? const Radius.circular(0)
                                : const Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['text'] ?? "",
                              style: GoogleFonts.poppins(
                                  color: Colors.white, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF181820),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textEditingController,
                    style:
                        GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: GoogleFonts.poppins(color: Colors.white54),
                        border: InputBorder.none),
                  ),
                ),
                IconButton(
                  onPressed: sendMessage,
                  icon: const Icon(Icons.send, color: Color(0xFFFF6B00)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
