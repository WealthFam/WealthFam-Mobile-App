import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';

class VaultDocument {
  final String id;
  final String filename;
  final String fileType;
  final String? description;
  final DateTime createdAt;
  final bool isFolder;
  final String? thumbnailPath;
  final String? mimeType;
  final double fileSize;
  final String? parentId;

  VaultDocument({
    required this.id,
    required this.filename,
    required this.fileType,
    this.description,
    required this.createdAt,
    this.isFolder = false,
    this.thumbnailPath,
    this.mimeType,
    this.fileSize = 0,
    this.parentId,
  });

  factory VaultDocument.fromJson(Map<String, dynamic> json) {
    return VaultDocument(
      id: json['id'],
      filename: json['filename'] ?? json['name'] ?? 'Untitled',
      fileType: json['file_type'] ?? 'OTHER',
      description: json['description'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toUtc().toIso8601String()).toLocal(),
      isFolder: json['is_folder'] ?? false,
      thumbnailPath: json['thumbnail_path'],
      mimeType: json['mime_type'],
      fileSize: (json['file_size'] as num?)?.toDouble() ?? 0,
      parentId: json['parent_id'],
    );
  }

  String get formattedSize {
    if (fileSize <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = fileSize;
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }
}

class VaultService extends ChangeNotifier {
  final AppConfig _config;
  final AuthService _auth;

  List<VaultDocument> _documents = [];
  bool _isLoading = false;
  String? _error;
  
  // Navigation stack for folders
  final List<String> _navigationStack = ["ROOT"];
  String get currentParentId => _navigationStack.last;
  bool get canGoBack => _navigationStack.length > 1;

  List<VaultDocument> get documents => _documents;
  bool get isLoading => _isLoading;
  String? get error => _error;

  VaultService(this._config, this._auth);

  String getThumbnailUrl(String docId) {
    return '${_config.backendUrl}/api/v1/finance/vault/$docId/thumbnail';
  }

  String getDownloadUrl(String docId) {
    return '${_config.backendUrl}/api/v1/finance/vault/$docId/download';
  }

  Map<String, String> get authHeaders => {
    'Authorization': 'Bearer ${_auth.accessToken}',
  };

  Future<void> fetchDocuments({String? parentId}) async {
    if (_auth.accessToken == null) return;

    final targetParentId = parentId ?? currentParentId;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final url = Uri.parse('${_config.backendUrl}/api/v1/finance/vault').replace(queryParameters: {
        'parent_id': targetParentId,
      });

      final response = await http.get(
        url,
        headers: {
          ...authHeaders,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _documents = data.map((e) => VaultDocument.fromJson(e)).toList();
        _error = null;
      } else {
        _error = 'Failed to load vault: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('Vault Error: $e');
      _error = 'Network error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void navigateToFolder(String folderId) {
    _navigationStack.add(folderId);
    fetchDocuments();
  }

  void goBack() {
    if (canGoBack) {
      _navigationStack.removeLast();
      fetchDocuments();
    }
  }
  
  Future<bool> deleteDocument(String docId) async {
    try {
      final response = await http.delete(
        Uri.parse('${_config.backendUrl}/api/v1/finance/vault/$docId'),
        headers: authHeaders,
      );
      if (response.statusCode == 200) {
        _documents.removeWhere((doc) => doc.id == docId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Delete Error: $e');
    }
    return false;
  }

  Future<bool> uploadDocument({
    required String filePath,
    required String fileName,
    String fileType = "OTHER",
    String? description,
    bool isShared = true,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final url = Uri.parse('${_config.backendUrl}/api/v1/finance/vault/upload');
      final request = http.MultipartRequest('POST', url)
        ..headers.addAll(authHeaders)
        ..fields['file_type'] = fileType
        ..fields['is_shared'] = isShared.toString()
        ..fields['parent_id'] = currentParentId;
      
      if (description != null) request.fields['description'] = description;
      
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchDocuments();
        return true;
      } else {
        debugPrint('Upload failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Upload Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> createFolder(String name) async {
    _isLoading = true;
    notifyListeners();

    try {
      final url = Uri.parse('${_config.backendUrl}/api/v1/finance/vault/folders');
      final request = http.MultipartRequest('POST', url)
        ..headers.addAll(authHeaders)
        ..fields['name'] = name
        ..fields['parent_id'] = currentParentId == "ROOT" ? "" : currentParentId;
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchDocuments();
        return true;
      }
    } catch (e) {
      debugPrint('Create Folder Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> renameDocument(String docId, String newName) async {
    _isLoading = true;
    notifyListeners();

    try {
      final url = Uri.parse('${_config.backendUrl}/api/v1/finance/vault/$docId');
      final request = http.MultipartRequest('PUT', url)
        ..headers.addAll(authHeaders)
        ..fields['filename'] = newName;
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        await fetchDocuments();
        return true;
      }
    } catch (e) {
      debugPrint('Rename Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<String?> saveDocument(VaultDocument doc) async {
    try {
      final response = await http.get(
        Uri.parse(getDownloadUrl(doc.id)),
        headers: authHeaders,
      );

      if (response.statusCode == 200) {
        final directory = kIsWeb 
          ? null // Web handles downloads differently
          : (await getApplicationDocumentsDirectory()).path;
        
        if (directory != null) {
          final file = File('$directory/${doc.filename}');
          await file.writeAsBytes(response.bodyBytes);
          return file.path;
        }
      }
    } catch (e) {
      debugPrint('Save Error: $e');
    }
    return null;
  }
}
