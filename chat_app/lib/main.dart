import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/sign_in_page.dart';
import 'services/repository_service.dart';
import 'services/navigator_service.dart';

/// Entry point that initializes the local-first stack then opens the right page.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RepositoryService().initialize().then((signedUser) {
    runApp(
      ChatApp(home: signedUser != null ? const HomePage() : const SignInPage()),
    );
  });
}

/// Root widget configuring theme and navigation key.
class ChatApp extends StatelessWidget {
  final Widget home;

  const ChatApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      navigatorKey: NavigatorService().navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: home,
    );
  }
}
