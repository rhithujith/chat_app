import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with SingleTickerProviderStateMixin {
  bool _permissionGranted = false;
  bool _isLoadingContacts = false;
  List<Contact> _phoneContacts = [];
  TabController? _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _profileChecked = false;
  bool _profileExists = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (!kIsWeb) {
      _checkContactsPermission();
    }
    _checkUserProfile();
  }

  Future<void> _checkUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _profileExists = false;
          _profileChecked = true;
        });
      }
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            _profileExists = true;
            _profileChecked = true;
          });
        }
      } else {
        // Auto-register profile in Firestore for authenticated user
        final phone = user.phoneNumber ?? '';
        final defaultName = phone.isNotEmpty ? 'User $phone' : 'User ${user.uid.substring(0, 6)}';
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'phone': phone,
          'name': defaultName,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() {
            _profileExists = true;
            _profileChecked = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking user profile: $e');
      if (mounted) {
        setState(() {
          _profileExists = false;
          _profileChecked = true;
        });
      }
    }
  }

  Future<void> _showRegistrationDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    final nameController = TextEditingController();
    final phoneController = TextEditingController(text: user?.phoneNumber ?? '');

    await showDialog(
      context: context,
      builder: (context) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: Colors.deepPurple),
                  SizedBox(width: 10),
                  Text('Register Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Register your details so friends can find and message you on Nudge.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'e.g. Alex Smith',
                      prefixIcon: const Icon(Icons.person, color: Colors.deepPurple),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'e.g. +919876543210',
                      prefixIcon: const Icon(Icons.phone, color: Colors.deepPurple),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                if (user == null)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text('Go to Login', style: TextStyle(color: Colors.grey)),
                  ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final phone = phoneController.text.trim();
                          if (name.isEmpty || phone.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter both name and phone number.')),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          try {
                            final targetUid = user?.uid ?? 'dev_${phone.replaceAll(RegExp(r'\D'), '')}';
                            await FirebaseFirestore.instance.collection('users').doc(targetUid).set({
                              'uid': targetUid,
                              'phone': phone,
                              'name': name,
                              'createdAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));

                            if (mounted) {
                              setState(() {
                                _profileExists = true;
                                _profileChecked = true;
                              });
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Profile successfully registered!')),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Registration failed: $e')),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Register', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _checkContactsPermission() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (mounted) {
        setState(() {
          _permissionGranted = granted;
        });
        if (granted) {
          _fetchPhoneContacts();
        }
      }
    } catch (e) {
      debugPrint('Error checking contacts permission: $e');
    }
  }

  Future<void> _requestContactsPermission() async {
    try {
      final granted = await FlutterContacts.requestPermission();
      if (mounted) {
        setState(() {
          _permissionGranted = granted;
        });
        if (granted) {
          _fetchPhoneContacts();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contacts permission error: $e')),
      );
    }
  }

  Future<void> _fetchPhoneContacts() async {
    if (kIsWeb) return;
    setState(() => _isLoadingContacts = true);
    try {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      if (mounted) {
        setState(() {
          _phoneContacts = contacts;
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingContacts = false);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading phone contacts: $e')),
      );
    }
  }

  Future<void> _seedDemoContacts() async {
    final List<Map<String, String>> demoContacts = [
      {'uid': 'demo_alice', 'name': 'Alice', 'phone': '+919876543210'},
      {'uid': 'demo_bob', 'name': 'Bob', 'phone': '+919123456789'},
      {'uid': 'demo_charlie', 'name': 'Charlie', 'phone': '+919988776655'},
      {'uid': 'demo_diana', 'name': 'Diana', 'phone': '+919871234560'},
    ];

    for (final contact in demoContacts) {
      await FirebaseFirestore.instance.collection('users').doc(contact['uid']).set({
        'uid': contact['uid'],
        'name': contact['name'],
        'phone': contact['phone'],
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  String _cleanPhoneNumber(String phone) {
    // Keep only numeric digits
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    // Take the last 10 digits (Standard Indian mobile number length) to resolve prefix variations
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid ?? 'bypass_user';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Nudge',
          style: TextStyle(
            color: Colors.deepPurple,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.deepPurple),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          )
        ],
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: !kIsWeb && _permissionGranted
            ? TabBar(
                controller: _tabController,
                labelColor: Colors.deepPurple,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.deepPurple,
                tabs: const [
                  Tab(icon: Icon(Icons.mark_chat_read), text: 'Nudge Friends'),
                  Tab(icon: Icon(Icons.contact_phone_outlined), text: 'Phone Contacts'),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          if (!_profileExists && _profileChecked)
            Container(
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              width: double.infinity,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Your profile is not registered in the database. Friends cannot find or message you.',
                      style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _showRegistrationDialog,
                    child: const Text('Register', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          // Premium Contact & Chat Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase().trim();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search contacts by name or phone...',
                prefixIcon: const Icon(Icons.search, color: Colors.deepPurple),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.deepPurple));
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final dbUsers = snapshot.data?.docs ?? [];
                var activeUsers = dbUsers.where((doc) => doc.id != currentUid).toList();

                // Apply search filter if query is not empty
                if (_searchQuery.isNotEmpty) {
                  activeUsers = activeUsers.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final String name = (data['name'] ?? '').toString().toLowerCase();
                    final String phone = (data['phone'] ?? '').toString();
                    return name.contains(_searchQuery) || phone.contains(_searchQuery);
                  }).toList();
                }

                // --- WEB OR NO NATIVE PERMISSION FLOW ---
                if (kIsWeb || !_permissionGranted) {
                  return _buildSimpleList(activeUsers);
                }

                // --- MOBILE MATCHING FLOW ---
                if (_isLoadingContacts) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.deepPurple),
                        SizedBox(height: 15),
                        Text('Syncing phone contacts...', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                // Extract all registered phone numbers and match them to Firestore documents
                final Set<String> registeredPhones = {};
                final Map<String, QueryDocumentSnapshot> phoneToUserMap = {};

                for (final userDoc in dbUsers.where((doc) => doc.id != currentUid).toList()) {
                  final data = userDoc.data() as Map<String, dynamic>;
                  final String phone = data['phone'] ?? '';
                  final String cleaned = _cleanPhoneNumber(phone);
                  if (cleaned.isNotEmpty) {
                    registeredPhones.add(cleaned);
                    phoneToUserMap[cleaned] = userDoc;
                  }
                }

                final List<Contact> matchedContacts = [];
                final List<Contact> unmatchedContacts = [];

                for (final contact in _phoneContacts) {
                  bool isMatched = false;
                  for (final phoneObj in contact.phones) {
                    final String cleanedLocal = _cleanPhoneNumber(phoneObj.number);
                    if (registeredPhones.contains(cleanedLocal)) {
                      matchedContacts.add(contact);
                      isMatched = true;
                      break;
                    }
                  }
                  if (!isMatched && contact.phones.isNotEmpty) {
                    unmatchedContacts.add(contact);
                  }
                }

                // Apply search filter to matched and unmatched contacts on mobile
                var displayMatched = matchedContacts;
                var displayUnmatched = unmatchedContacts;

                if (_searchQuery.isNotEmpty) {
                  displayMatched = displayMatched.where((contact) {
                    final name = contact.displayName.toLowerCase();
                    final phones = contact.phones.map((p) => p.number).join(' ');
                    return name.contains(_searchQuery) || phones.contains(_searchQuery);
                  }).toList();

                  displayUnmatched = displayUnmatched.where((contact) {
                    final name = contact.displayName.toLowerCase();
                    final phones = contact.phones.map((p) => p.number).join(' ');
                    return name.contains(_searchQuery) || phones.contains(_searchQuery);
                  }).toList();
                }

                return TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Friends on Nudge (Firestore matched)
                    _buildMatchedTab(displayMatched, phoneToUserMap, activeUsers),
                    // Tab 2: Native Phone Book (Unmatched - Invitation Style)
                    _buildPhoneBookTab(displayUnmatched),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Fallback view for Web or when Contacts permissions are not synced
  Widget _buildSimpleList(List<QueryDocumentSnapshot> activeUsers) {
    return Column(
      children: [
        if (!kIsWeb)
          Card(
            margin: const EdgeInsets.all(15),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.contacts_rounded, color: Colors.deepPurple, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sync Your Contacts',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nudge can check your device phone book to instantly find your friends who are already using the app.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      onPressed: _requestContactsPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Access Phone Contacts', style: TextStyle(color: Colors.white)),
                    ),
                  )
                ],
              ),
            ),
          ),
        if (kIsWeb)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Colors.deepPurple.shade50,
            width: double.infinity,
            child: const Row(
              children: [
                Icon(Icons.web, color: Colors.deepPurple),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Web Mode: Displaying all active registered database users. Native contacts permission is available on mobile devices.',
                    style: TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: activeUsers.isEmpty ? _buildEmptyDbState() : _buildUsersList(activeUsers),
        ),
      ],
    );
  }

  Widget _buildUsersList(
    List<QueryDocumentSnapshot> users, {
    bool shrinkWrap = false,
    ScrollPhysics? physics,
  }) {
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: users.length,
      itemBuilder: (context, index) {
        final userDoc = users[index];
        final data = userDoc.data() as Map<String, dynamic>;
        final String name = data['name'] ?? 'User';
        final String phone = data['phone'] ?? '';
        final String uid = data['uid'] ?? userDoc.id;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.deepPurple,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(phone),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  contactName: name,
                  contactPhone: phone,
                  contactUid: uid,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMatchedTab(
    List<Contact> matched,
    Map<String, QueryDocumentSnapshot> phoneToUserMap,
    List<QueryDocumentSnapshot> fallbackUsers,
  ) {
    if (matched.isEmpty) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_search_rounded, size: 70, color: Colors.grey),
              const SizedBox(height: 15),
              const Text(
                'None of your phone contacts are on Nudge yet!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Go to the "Phone Contacts" tab to invite them, or select a demo user below to test real-time messaging:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              _buildUsersList(
                fallbackUsers,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: matched.length,
      itemBuilder: (context, index) {
        final contact = matched[index];
        final phoneNum = contact.phones.first.number;
        final String cleaned = _cleanPhoneNumber(phoneNum);
        final userDoc = phoneToUserMap[cleaned]!;
        final data = userDoc.data() as Map<String, dynamic>;
        final String dbUid = data['uid'] ?? userDoc.id;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.deepPurple,
            child: Text(
              contact.displayName.isNotEmpty ? contact.displayName[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('On Nudge • $phoneNum'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  contactName: contact.displayName,
                  contactPhone: phoneNum,
                  contactUid: dbUid,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _inviteViaWhatsApp(String phoneName, String rawPhone) async {
    // 1. Clean the phone number for WhatsApp wa.me API (digits only)
    String waPhone = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (waPhone.startsWith('00')) {
      waPhone = waPhone.substring(2);
    }

    // Auto-detect and prepend India country code (91) for standard local 10-digit numbers
    if (waPhone.length == 10) {
      waPhone = '91$waPhone';
    } else if (waPhone.length == 11 && waPhone.startsWith('0')) {
      waPhone = '91${waPhone.substring(1)}';
    }

    // 2. Draft the invite message with the GitHub link
    final String message = "Hi $phoneName! I'm using Nudge, a secure real-time messaging app. Download the app directly from our GitHub repository to start chatting: https://github.com/rhithujith/chat_app";

    // 3. Construct wa.me URL
    final Uri url = Uri.parse("https://wa.me/$waPhone?text=${Uri.encodeComponent(message)}");

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch WhatsApp API URL';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open WhatsApp: $e')),
        );
      }
    }
  }

  Widget _buildPhoneBookTab(List<Contact> unmatched) {
    if (unmatched.isEmpty) {
      return const Center(
        child: Text('All your phone book contacts are already using Nudge!', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: unmatched.length,
      itemBuilder: (context, index) {
        final contact = unmatched[index];
        final String phoneNum = contact.phones.isNotEmpty ? contact.phones.first.number : '';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey.shade400,
            child: Text(
              contact.displayName.isNotEmpty ? contact.displayName[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
          subtitle: Text(phoneNum, style: const TextStyle(color: Colors.grey)),
          trailing: TextButton(
            onPressed: () => _inviteViaWhatsApp(contact.displayName, phoneNum),
            child: const Text('Invite', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildEmptyDbState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            const Text(
              'No registered users found.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Click the button below to seed test contacts so you can start chatting instantly!',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _seedDemoContacts,
              icon: const Icon(Icons.cloud_download, color: Colors.white),
              label: const Text('Seed Test Contacts', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}