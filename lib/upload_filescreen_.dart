import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:upload_date_api/uploadserver.dart';
import 'file_service.dart';

class UploadFileScreen extends StatefulWidget {
  const UploadFileScreen({super.key});

  @override
  State<UploadFileScreen> createState() => _UploadFileScreenState();
}

class _UploadFileScreenState extends State<UploadFileScreen> {
  final _picker = ImagePicker();
  List<File> pickedImages = [];
  bool _isPicking = false;
  bool _isUploading = false;
  bool isLoading = false;
  List<Map<String, dynamic>> uploadedImages = [];

  static const String baseUrl = 'http://10.0.2.2:4000';

  @override
  void initState() {
    super.initState();
    fetchUploadedImages();
  }

  Future<List<XFile>?> pickImages({
    ImageSource source = ImageSource.gallery,
    required ScaffoldMessengerState scaffoldMessenger,
  }) async {
    if (_isPicking) {
      print("Already picking images, returning null.");
      return null;
    }
    _isPicking = true;

    try {
      if (source == ImageSource.camera) {
        final camStatus = await Permission.camera.status;
        if (camStatus.isDenied) {
          final cam = await Permission.camera.request();
          if (!cam.isGranted) {
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: const Text('Camera permission is required. Please enable it in settings.'),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () async => await openAppSettings(),
                ),
              ),
            );
            return null;
          }
        } else if (camStatus.isPermanentlyDenied) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: const Text('Camera permission is required. Please enable it in settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () async => await openAppSettings(),
              ),
            ),
          );
          return null;
        }

        final xFile = await _picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 2000,
        );
        if (xFile != null) {
          final file = File(xFile.path);
          await PhotoManager.editor.saveImage(
            await file.readAsBytes(),
            title: 'MyAppPhoto_${DateTime.now().millisecondsSinceEpoch}.jpg',
            filename: 'MyAppPhoto_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          return [xFile];
        }
        return null;
      } else {
        final photosStatus = await Permission.photos.status;
        if (photosStatus.isDenied || photosStatus.isLimited) {
          final photos = await Permission.photos.request();
          if (!(photos.isGranted || photos.isLimited)) {
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: const Text('Photo access is required. Please enable it in settings.'),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () async => await openAppSettings(),
                ),
              ),
            );
            return null;
          }
        } else if (photosStatus.isPermanentlyDenied) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: const Text('Photo access is required. Please enable it in settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () async => await openAppSettings(),
              ),
            ),
          );
          return null;
        }

        final xFiles = await _picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 2000,
        );
        return xFiles;
      }
    } catch (e, stackTrace) {
      print("Error in pickImages: $e");
      print("Stack trace: $stackTrace");
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed to pick images: $e')));
      return null;
    } finally {
      _isPicking = false;
    }
  }

  Future<void> uploadImages(List<File> files) async {
    if (_isUploading) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No images selected to upload')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final formData = FormData();
      for (var file in files) {
        formData.files.add(
          MapEntry(
            'files',
            await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
          ),
        );
      }

      final response = await UploadApi.uploadFiles(formData);

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded ${files.length} images successfully!')),
        );
        setState(() {
          pickedImages.clear();
        });
        await fetchUploadedImages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload images: ${response.statusMessage ?? "Unknown error"}')),
        );
      }
    } catch (e) {
      print("Error in uploadImages: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload images: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> fetchUploadedImages() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await UploadApi.listFiles();

      if (response.statusCode == 200) {
        final data = response.data;

        if (data is Map && data.containsKey('files') && data['files'] is List) {
          setState(() {
            uploadedImages = List<Map<String, dynamic>>.from(data['files'].map((file) => Map<String, dynamic>.from(file)));
          });
          print("Fetched ${uploadedImages.length} images successfully");
        } else {
          print("Unexpected response format: $data");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to fetch images: Invalid response format')),
          );
        }
      } else {
        print("Failed to fetch images: ${response.statusCode} - ${response.statusMessage}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch images: ${response.statusMessage ?? "Unknown error"}')),
        );
      }
    } catch (e, stack) {
      print("Error fetching images: $e");
      print(stack);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch images: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> downloadImage(String fileUrl) async {
    try {
      final file = await FileService.downloadToAppDir(fileUrl, saveToGallery: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Downloaded to: ${file.path}")),
      );
    } catch (e) {
      print("Error downloading image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to download image: $e"),
          action: e.toString().contains('permission')
              ? SnackBarAction(
            label: 'Settings',
            onPressed: () async => await openAppSettings(),
          )
              : null,
        ),
      );
    }
  }

  Future<void> deleteImage(String filename) async {
    try {
      final response = await UploadApi.deleteFile(filename);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $filename')),
        );
        await fetchUploadedImages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${response.statusMessage ?? "Unknown error"}')),
        );
      }
    } catch (e) {
      print("Error deleting image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete image: $e')),
      );
    }
  }

  Future<void> showImageSource() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Choose image source",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        fixedSize: const Size(60, 60),
                        backgroundColor: Colors.blueGrey,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        final xFile = await pickImages(
                          source: ImageSource.camera,
                          scaffoldMessenger: scaffoldMessenger,
                        );
                        if (xFile != null && xFile.isNotEmpty) {
                          setState(() {
                            pickedImages = xFile.map((xFile) => File(xFile.path)).toList();
                          });
                        }
                      },
                      icon: const Icon(Icons.camera, color: Colors.white),
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        fixedSize: const Size(60, 60),
                        backgroundColor: Colors.blueGrey,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        final xFiles = await pickImages(
                          source: ImageSource.gallery,
                          scaffoldMessenger: scaffoldMessenger,
                        );
                        if (xFiles != null && xFiles.isNotEmpty) {
                          setState(() {
                            pickedImages = xFiles.map((xFile) => File(xFile.path)).toList();
                          });
                        }
                      },
                      icon: const Icon(Icons.photo, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Upload'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 200,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.blueGrey.withOpacity(0.1),
              ),
              child: pickedImages.isEmpty
                  ? const Center(
                child: Text(
                  'No images selected\nTap "Pick images" to select',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.blueGrey),
                ),
              )
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: pickedImages.length,
                itemBuilder: (context, index) {
                  return Image.file(
                    pickedImages[index],
                    fit: BoxFit.cover,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _isUploading ? null : showImageSource,
              child: const Text("Pick images", style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _isUploading || pickedImages.isEmpty
                  ? null
                  : () async => await uploadImages(pickedImages),
              child: Text(
                _isUploading ? "Uploading..." : "Upload images",
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Uploaded Images",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : uploadedImages.isEmpty
                  ? const Center(
                child: Text(
                  "No images uploaded yet",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              )
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: uploadedImages.length,
                itemBuilder: (context, index) {
                  final img = uploadedImages[index];
                  final fileUrl = "$baseUrl/files/${img['filename']}";
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      InkWell(
                        onTap: () => downloadImage(fileUrl),
                        child: Image.network(
                          fileUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () => deleteImage(img['filename']),
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}