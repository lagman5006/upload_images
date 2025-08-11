import 'dart:developer';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class FileService {
  static Future<File> downloadToAppDir(String fileUrl, {bool saveToGallery = true}) async {
    try {
      // Validate URL
      final uri = Uri.tryParse(fileUrl);
      if (uri == null) {
        throw Exception('Invalid URL: $fileUrl');
      }

      if (Platform.isAndroid && saveToGallery) {
        final permission = await _requestStoragePermission();
        if (!permission.isGranted) {
          throw Exception('Storage permission denied. Please enable it in settings.');
        }
      } else if (Platform.isIOS && saveToGallery) {
        final permission = await _requestPhotosPermission();
        if (!permission.isGranted) {
          throw Exception('Photo library permission denied. Please enable it in settings.');
        }
      }

      // Download the file
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('Download failed ${res.statusCode}: ${res.reasonPhrase}');
      }

      // Generate unique file name with timestamp
      final fileName = '${p.basenameWithoutExtension(uri.path)}_${DateTime.now().millisecondsSinceEpoch}${p.extension(uri.path)}';

      // Save to app's documents directory as a fallback
      final dir = await getApplicationDocumentsDirectory();
      final savePath = p.join(dir.path, fileName);
      final file = File(savePath);
      await file.writeAsBytes(res.bodyBytes);
      log('Saved to app directory: $savePath');

      // Save to Photos/Gallery if requested
      if (saveToGallery) {
        try {
          final savedFile = await PhotoManager.editor.saveImage(
            res.bodyBytes,
            title: fileName,
            filename: fileName,
          );
          log('Saved to gallery: ${savedFile.id}');
          return File(savedFile.id);
                } catch (e) {
          log('Error saving to gallery: $e');
          // Fallback to returning the file in app directory
          return file;
        }
      }

      return file;
    } catch (e) {
      log(' Error downloading file: $e');
      rethrow; // Rethrow to allow calling code to handle the error
    }
  }

  static Future<PermissionStatus> _requestStoragePermission() async {
    // Use Permission.photos for Android 13+, Permission.storage for older versions
    final permission = Platform.isAndroid && await _isAndroid13OrAbove()
        ? Permission.photos
        : Permission.storage;

    final status = await permission.status;
    if (status.isDenied) {
      return await permission.request();
    } else if (status.isPermanentlyDenied) {
      return status;
    }
    return status;
  }

  static Future<PermissionStatus> _requestPhotosPermission() async {
    final status = await Permission.photos.status;
    if (status.isDenied || status.isLimited) {
      return await Permission.photos.request();
    } else if (status.isPermanentlyDenied) {
      return status;
    }
    return status;
  }

  static Future<bool> _isAndroid13OrAbove() async {
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      return deviceInfo.version.sdkInt >= 33;
    }
    return false;
  }
}