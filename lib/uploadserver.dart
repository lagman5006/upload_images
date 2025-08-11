import 'package:dio/dio.dart';

class UploadApi {
  static final _dio = Dio(BaseOptions(baseUrl: 'https://c9239661112a.ngrok-free.app'));

  static Future<Response> listFiles() => _dio.get('/files');

  static Future<Response> uploadFiles(FormData formData) => _dio.post(
    '/upload',
    data: formData,
    options: Options(headers: {'Content-Type': 'multipart/form-data'}),
  );

  static Future<Response> deleteFile(String filename) => _dio.delete('/files/$filename');
}