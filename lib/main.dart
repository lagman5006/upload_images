import 'package:flutter/material.dart';
import 'package:upload_date_api/upload_filescreen_.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: UploadFileScreen(),
    );
  }
}
