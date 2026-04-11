import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/core/errors/either.dart';
import 'package:mobile_app/core/errors/failures.dart';
import 'package:mobile_app/core/utils/network_resilience.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class VaultService extends ChangeNotifier with NetworkResilience {
  final AppConfig _config;
  final AuthService _auth;

  List<VaultDocument> _documents = [];
  bool _isLoading = false;
  String? _error;
  
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

  String get _cacheKey => 'vault_cache_${currentParentId}';

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson != null) {
        final List<dynamic> data = jsonDecode(cachedJson);
        _documents = data.map((e) => VaultDocument.fromJson(e)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('VaultService: Error loading cache: $e');
    }
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _documents.map((e) => {
        'id': e.id,
        'filename': e.filename,
        'file_type': e.fileType,
        'description': e.description,
        'created_at': e.createdAt.toUtc().toIso8601String(),
        'is_folder': e.isFolder,
        'thumbnail_path': e.thumbnailPath,
        'mime_type': e.mimeType,
        'file_size': e.fileSize,
        'parent_id': e.parentId,
      }).toList();
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      debugPrint('VaultService: Error saving cache: $e');
    }
  }

  Future<void> fetchDocuments({String? parentId}) async {
    if (_auth.accessToken == null) return;

    final targetParentId = parentId ?? currentParentId;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await callWithResilience<List<VaultDocument>>(
      call: () => http.get(
        Uri.parse('${_config.backendUrl}/api/v1/finance/vault').replace(queryParameters: {
          'parent_id': targetParentId,
        }),
        headers: {
          ...authHeaders,
          'Content-Type': 'application/json',
        },
      ),
      onSuccess: (body) {
        final List<dynamic> data = jsonDecode(body);
        return data.map((e) => VaultDocument.fromJson(e)).toList();
      },
    );

    await result.fold(
      (failure) async {
        _error = failure.message;
        if (_documents.isEmpty) {
          await _loadCache();
        }
      },
      (docs) async {
        _documents = docs;
        _error = null;
        await _saveCache();
      },
    );

    _isLoading = false;
    notifyListeners();
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
  
  Future<Either<Failure, Unit>> deleteDocument(String docId) async {
    final result = await callWithResilience<Unit>(
      call: () => http.delete(
        Uri.parse('${_config.backendUrl}/api/v1/finance/vault/$docId'),
        headers: authHeaders,
      ),
      onSuccess: (_) {
        _documents.removeWhere((doc) => doc.id == docId);
        notifyListeners();
        return unit;
      },
    );
    return result;
  }

  Future<Either<Failure, Unit>> uploadDocument({
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
        _isLoading = false;
        notifyListeners();
        return const Right(unit);
      } else {
        _isLoading = false;
        notifyListeners();
        return Left(ServerFailure('Upload failed: ${response.statusCode}'));
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Unit>> createFolder(String name) async {
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
        _isLoading = false;
        notifyListeners();
        return const Right(unit);
      }
      _isLoading = false;
      notifyListeners();
      return Left(ServerFailure('Failed to create folder: ${response.statusCode}'));
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Unit>> renameDocument(String docId, String newName) async {
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
        _isLoading = false;
        notifyListeners();
        return const Right(unit);
      }
      _isLoading = false;
      notifyListeners();
      return Left(ServerFailure('Rename failed: ${response.statusCode}'));
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, String>> saveDocument(VaultDocument doc) async {
    try {
      final response = await http.get(
        Uri.parse(getDownloadUrl(doc.id)),
        headers: authHeaders,
      );

      if (response.statusCode == 200) {
        final directory = kIsWeb 
          ? null 
          : (await getApplicationDocumentsDirectory()).path;
        
        if (directory != null) {
          final file = File('$directory/${doc.filename}');
          await file.writeAsBytes(response.bodyBytes);
          return Right(file.path);
        }
        return const Left(CacheFailure('Could not access storage'));
      }
      return Left(ServerFailure('Download failed: ${response.statusCode}'));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
