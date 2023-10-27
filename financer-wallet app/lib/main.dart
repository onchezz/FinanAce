import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:starknet/starknet.dart';
import 'package:starknet_flutter/starknet_flutter.dart';

import 'ui/screens/account_balance/home.dart';

Future<void> main() async {
  const nodeUri = String.fromEnvironment('NODE_URI');
  await StarknetFlutter.init(
    nodeUri: (nodeUri.isNotEmpty) ? Uri.parse(nodeUri) : infuraGoerliTestnetUri,
  );

  runApp(const StarknetWalletApp());
}

class StarknetWalletApp extends StatelessWidget {
  const StarknetWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "StarkNet Wallet in Flutter",
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        primarySwatch: Colors.blue,
        fontFamily: GoogleFonts.poppins().fontFamily,
      ),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}
