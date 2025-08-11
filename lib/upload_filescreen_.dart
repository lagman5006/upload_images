import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart'; // Import photo_manager

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
  final Dio _dio = Dio();

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
        print("Checking camera permission...");
        final camStatus = await Permission.camera.status;
        print("Camera permission status: $camStatus");
        if (camStatus.isDenied) {
          print("Requesting camera permission...");
          final cam = await Permission.camera.request();
          print("Camera permission request result: $cam");
          if (!cam.isGranted) {
            if (cam.isPermanentlyDenied) {
              print("Camera permission permanently denied, opening settings...");
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Camera permission is required. Please enable it in settings.'),
                  action: SnackBarAction(
                    label: 'Settings',
                    onPressed: openAppSettings,
                  ),
                ),
              );
              return null;
            } else {
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('Camera permission denied')),
              );
              return null;
            }
          }
        } else if (camStatus.isPermanentlyDenied) {
          print("Camera permission already permanently denied, opening settings...");
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required. Please enable it in settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: openAppSettings,
              ),
            ),
          );
          return null;
        }
        print("Attempting to pick image from camera...");
        final xFile = await _picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 2000,
        );
        print("Image picker result: ${xFile?.path ?? 'null'}");
        if (xFile != null) {
          // Save the camera image to the gallery using photo_manager
          print("Saving image to gallery...");
          final file = File(xFile.path);
          final saved = await PhotoManager.editor.saveImage(
            await file.readAsBytes(),
            title: 'MyAppPhoto_${DateTime.now().millisecondsSinceEpoch}.jpg', filename: '',
          );
          if (saved != null) {
            print("Image saved to gallery successfully");
            scaffoldMessenger.showSnackBar(
              const SnackBar(content: Text('Image saved to gallery')),
            );
          } else {
            print("Failed to save image to gallery");
            scaffoldMessenger.showSnackBar(
              const SnackBar(content: Text('Failed to save image to gallery')),
            );
          }
          return [xFile];
        }
        return null;
      } else {
        print("Checking photos permission...");
        final photosStatus = await Permission.photos.status;
        print("Photos permission status: $photosStatus");
        if (photosStatus.isDenied) {
          print("Requesting photos permission...");
          final photos = await Permission.photos.request();
          print("Photos permission request result: $photos");
          if (!(photos.isGranted || photos.isLimited)) {
            if (photos.isPermanentlyDenied) {
              print("Photos permission permanently denied, opening settings...");
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Photo access is required. Please enable it in settings.'),
                  action: SnackBarAction(
                    label: 'Settings',
                    onPressed: openAppSettings,
                  ),
                ),
              );
              return null;
            } else {
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('Photo permission denied')),
              );
              return null;
            }
          }
        } else if (photosStatus.isPermanentlyDenied) {
          print("Photos permission already permanently denied, opening settings...");
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Photo access is required. Please enable it in settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: openAppSettings,
              ),
            ),
          );
          return null;
        }
        print("Attempting to pick multiple images from gallery...");
        final xFiles = await _picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 2000,
        );
        print("Image picker result: ${xFiles.map((x) => x.path).toList()}");
        if (xFiles.isEmpty && photosStatus.isLimited) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Limited access granted. Please select images or allow full access in settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: openAppSettings,
              ),
            ),
          );
        }
        return xFiles;
      }
    } catch (e, stackTrace) {
      print("Error in pickImages: $e");
      print("Stack trace: $stackTrace");
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return null;
    } finally {
      _isPicking = false;
    }
  }

  Future<void> uploadImages(List<File> files) async {
    if (_isUploading) {
      print("Already uploading, please wait.");
      return;
    }
    if (files.isEmpty) {
      print("No images to upload.");
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
        formData.files.add(MapEntry(
          'files',
          await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
        ));
      }

      const uploadUrl = 'https://d44ff53a0f09.ngrok-free.app/upload';
      print("Uploading ${files.length} images to $uploadUrl...");
      final response = await _dio.post(
        uploadUrl,
        data: formData,
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      print("Upload response: ${response.statusCode} - ${response.data}");
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded ${files.length} images successfully!')),
        );
        setState(() {
          pickedImages.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload images: ${response.statusMessage}')),
        );
      }
    } catch (e, stackTrace) {
      print("Error in uploadImages: $e");
      print("Stack trace: $stackTrace");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading images: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
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
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
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
                        } else {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(content: Text('No image selected from camera')),
                          );
                        }
                      },
                      icon: const Icon(Icons.camera),
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
                        } else {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(content: Text('No images selected from gallery')),
                          );
                        }
                      },
                      icon: const Icon(Icons.photo),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              height: 300,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: Colors.blueGrey,
              ),
              child: pickedImages.isEmpty
                  ? const Icon(Icons.image, size: 60, color: Colors.white)
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: pickedImages.length,
                itemBuilder: (context, index) {
                  return Image.file(pickedImages[index], fit: BoxFit.cover);
                },
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
              ),
              onPressed: _isUploading ? null : showImageSource,
              child: const Text("Pick images", style: TextStyle(fontSize: 30)),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
              ),
              onPressed: _isUploading || pickedImages.isEmpty
                  ? null
                  : () async {
                await uploadImages(pickedImages);
              },
              child: Text(
                _isUploading ? "Uploading..." : "Upload images",
                style: const TextStyle(fontSize: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}