import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/errors/either.dart';
import 'package:mobile_app/core/errors/failures.dart';
import 'package:mobile_app/core/utils/network_resilience.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LinkedTransaction {
  LinkedTransaction({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    this.category,
    this.accountName,
  });

  factory LinkedTransaction.fromJson(Map<String, dynamic> json) {
    return LinkedTransaction(
      id: json['id'] as String,
      description: (json['description'] as String?) ?? 'No description',
      amount: Decimal.parse((json['amount'] ?? 0).toString()),
      date: DateTime.parse(
        (json['date'] as String?) ?? DateTime.now().toUtc().toIso8601String(),
      ).toLocal(),
      category: json['category'] as String?,
      accountName: json['account_name'] as String?,
    );
  }

  final String id;
  final String description;
  final Decimal amount;
  final DateTime date;
  final String? category;
  final String? accountName;
}

class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.filename,
    required this.fileType,
    required this.createdAt,
    this.description,
    this.isFolder = false,
    this.thumbnailPath,
    this.mimeType,
    this.fileSize = 0,
    this.parentId,
    this.transactionId,
    this.linkedTransaction,
  });

  factory VaultDocument.fromJson(Map<String, dynamic> json) {
    return VaultDocument(
      id: json['id'] as String,
      filename: (json['filename'] as String?) ?? (json['name'] as String?) ?? 'Untitled',
      fileType: (json['file_type'] as String?) ?? 'OTHER',
      description: json['description'] as String?,
      createdAt: DateTime.parse(
        (json['created_at'] as String?) ?? DateTime.now().toUtc().toIso8601String(),
      ).toLocal(),
      isFolder: (json['is_folder'] as bool?) ?? false,
      thumbnailPath: json['thumbnail_path'] as String?,
      mimeType: json['mime_type'] as String?,
      fileSize: (json['file_size'] as num?)?.toDouble() ?? 0,
      parentId: json['parent_id'] as String?,
      transactionId: json['transaction_id'] as String?,
      linkedTransaction: json['transaction'] != null
          ? LinkedTransaction.fromJson(json['transaction'] as Map<String, dynamic>)
          : null,
    );
  }

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
  final String? transactionId;
  final LinkedTransaction? linkedTransaction;

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
  VaultService(this._config, this._auth);

  final AppConfig _config;
  final AuthService _auth;

  List<VaultDocument> _documents = [];
  bool _isLoading = false;
  String? _error;

  // Navigation & Breadcrumbs
  final List<Map<String, String>> _navigationStack = [
    {'id': 'ROOT', 'name': 'Vault'},
  ];

  List<Map<String, String>> get breadcrumbs =>
      List.unmodifiable(_navigationStack);
  String get currentParentId => _navigationStack.last['id']!;
  String get currentFolderName => _navigationStack.last['name']!;
  bool get canGoBack => _navigationStack.length > 1;

  // Selection state
  final Set<String> _selectedIds = {};
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get isSelectionMode => _selectedIds.isNotEmpty;

  List<VaultDocument> get documents => _documents;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String _fileType = 'ALL';
  String get fileType => _fileType;

  void setFileType(String type) {
    _fileType = type;
    fetchDocuments();
  }

  String getThumbnailUrl(String docId) {
    return '${_config.backendUrl}/api/v1/mobile/vault/$docId/thumbnail';
  }

  String getDownloadUrl(String docId) {
    return '${_config.backendUrl}/api/v1/mobile/vault/$docId/download';
  }

  Map<String, String> get authHeaders => {
    'Authorization': 'Bearer ${_auth.accessToken}',
  };

  String get _cacheKey => 'vault_cache_$currentParentId';

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson != null) {
        final List<dynamic> data = (jsonDecode(cachedJson) as List<dynamic>?) ?? [];
        _documents = data.map((e) => VaultDocument.fromJson(e as Map<String, dynamic>)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('VaultService: Error loading cache: $e');
    }
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _documents
          .map(
            (e) => {
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
            },
          )
          .toList();
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      debugPrint('VaultService: Error saving cache: $e');
    }
  }

  Future<void> fetchDocuments({String? parentId, String? search}) async {
    if (_auth.accessToken == null) return;

    final targetParentId = search != null
        ? null
        : (parentId ?? currentParentId);

    _isLoading = true;
    _error = null;
    notifyListeners();

    final queryParams = <String, String>{};
    if (search != null) {
      queryParams['search'] = search;
    } else {
      queryParams['parent_id'] = targetParentId!;
    }

    if (_fileType != 'ALL') {
      queryParams['file_type'] = _fileType;
    }

    final result = await callWithResilience<List<VaultDocument>>(
      call: () => http.get(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/vault',
        ).replace(queryParameters: queryParams),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
      ),
      onSuccess: (body) async {
        final Map<String, dynamic> responseData = jsonDecode(body as String) as Map<String, dynamic>;
        final List<dynamic> itemsData = (responseData['data'] as List<dynamic>?) ?? [];
        final docs = itemsData.map((e) => VaultDocument.fromJson(e as Map<String, dynamic>)).toList();
        _documents = docs;
        _error = null;
        await _saveCache();
        return docs;
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

  Future<List<VaultDocument>> getLinkedDocuments(String transactionId) async {
    if (_auth.accessToken == null) return [];

    final result = await callWithResilience<List<VaultDocument>>(
      call: () => http.get(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/vault',
        ).replace(queryParameters: {'transaction_id': transactionId}),
        headers: authHeaders,
      ),
      onSuccess: (body) async {
        final Map<String, dynamic> responseData =
            jsonDecode(body as String) as Map<String, dynamic>;
        final List<dynamic> itemsData = (responseData['data'] as List<dynamic>?) ?? [];
        return itemsData
            .map((e) => VaultDocument.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );

    return result.fold((failure) => [], (docs) => docs);
  }

  Future<List<VaultDocument>> getFolders() async {
    if (_auth.accessToken == null) return [];

    final result = await callWithResilience<List<VaultDocument>>(
      call: () => http.get(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/vault').replace(
          queryParameters: {
            'is_folder': 'true',
            'parent_id': 'ALL', // Special value or just ignore parent?
          },
        ),
        headers: authHeaders,
      ),
      onSuccess: (body) async {
        final Map<String, dynamic> responseData =
            jsonDecode(body as String) as Map<String, dynamic>;
        final List<dynamic> itemsData = (responseData['data'] as List<dynamic>?) ?? [];
        return itemsData
            .map((e) => VaultDocument.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );

    return result.fold((failure) => [], (docs) => docs);
  }

  void navigateToFolder(String folderId, String folderName) {
    _navigationStack.add({'id': folderId, 'name': folderName});
    _selectedIds.clear();
    fetchDocuments();
  }

  void navigateToBreadcrumb(int index) {
    if (index < 0 || index >= _navigationStack.length) return;
    _navigationStack.removeRange(index + 1, _navigationStack.length);
    _selectedIds.clear();
    fetchDocuments();
  }

  void goBack() {
    if (canGoBack) {
      _navigationStack.removeLast();
      _selectedIds.clear();
      fetchDocuments();
    }
  }

  // Selection Actions
  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  Future<Either<Failure, Unit>> bulkDelete() async {
    if (_selectedIds.isEmpty) return const Right(unit);

    _isLoading = true;
    notifyListeners();

    final List<String> idsToDelete = _selectedIds.toList();
    int successCount = 0;

    for (final id in idsToDelete) {
      final result = await deleteDocument(id);
      if (result.isRight) successCount++;
    }

    _selectedIds.clear();
    _isLoading = false;
    notifyListeners();

    if (successCount == idsToDelete.length) {
      return const Right(unit);
    } else {
      return Left(
        ServerFailure(
          'Only $successCount of ${idsToDelete.length} items deleted',
        ),
      );
    }
  }

  Future<Either<Failure, Unit>> deleteDocument(String docId) async {
    final result = await callWithResilience<Unit>(
      call: () => http.delete(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/vault/$docId'),
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

  Future<Either<Failure, Unit>> moveDocuments(
    List<String> docIds,
    String targetParentId,
  ) async {
    _isLoading = true;
    notifyListeners();

    final result = await callWithResilience<Unit>(
      call: () => http.patch(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/vault/move'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'doc_ids': docIds,
          'target_parent_id': targetParentId == 'ROOT' ? null : targetParentId,
        }),
      ),
      onSuccess: (_) {
        _selectedIds.clear();
        fetchDocuments();
        return unit;
      },
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Either<Failure, Unit>> linkTransaction(
    String docId,
    String? transactionId,
  ) async {
    _isLoading = true;
    notifyListeners();

    final result = await callWithResilience<Unit>(
      call: () => http.patch(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/vault/$docId/link-transaction',
        ),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'transaction_id': transactionId}),
      ),
      onSuccess: (body) async {
        final updatedDoc = VaultDocument.fromJson(jsonDecode(body as String) as Map<String, dynamic>);
        final index = _documents.indexWhere((d) => d.id == updatedDoc.id);
        if (index != -1) {
          _documents[index] = updatedDoc;
          notifyListeners();
        }
        return unit;
      },
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Either<Failure, Unit>> uploadDocument({
    required String filePath,
    required String fileName,
    String fileType = 'OTHER',
    String? description,
    bool isShared = true,
    String? transactionId,
    String? parentId,
  }) async {
    _isLoading = true;
    notifyListeners();

    final url = Uri.parse('${_config.backendUrl}/api/v1/mobile/vault/upload');

    final result = await callWithResilience<Unit>(
      call: () async {
        final request = http.MultipartRequest('POST', url)
          ..headers.addAll(authHeaders)
          ..fields['file_type'] = fileType
          ..fields['is_shared'] = isShared.toString();

        final targetParent =
            parentId ?? (currentParentId == 'ROOT' ? '' : currentParentId);
        if (targetParent.isNotEmpty) {
          request.fields['parent_id'] = targetParent;
        }

        if (transactionId != null) {
          request.fields['transaction_id'] = transactionId;
        }

        if (description != null) request.fields['description'] = description;
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: fileName,
          ),
        );

        final streamedResponse = await request.send();
        return await http.Response.fromStream(streamedResponse);
      },
      onSuccess: (_) async {
        await fetchDocuments();
        return unit;
      },
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<String?> getOrCreateFolderByName(
    String name, {
    String? parentId,
  }) async {
    try {
      final url = Uri.parse(
        '${_config.backendUrl}/api/v1/mobile/vault',
      ).replace(queryParameters: {'parent_id': parentId ?? ''});

      final response = await http.get(url, headers: authHeaders);
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> data = (responseData['data'] as List<dynamic>?) ?? [];
        for (var itemRaw in data) {
          final item = itemRaw as Map<String, dynamic>;
          if (item['is_folder'] == true &&
              (item['filename'] as String? ?? item['name'] as String?) == name) {
            return item['id'] as String?;
          }
        }
      }

      // Not found, create it
      final createUrl = Uri.parse(
        '${_config.backendUrl}/api/v1/mobile/vault/folders',
      );
      final request = http.MultipartRequest('POST', createUrl)
        ..headers.addAll(authHeaders)
        ..fields['name'] = name;

      if (parentId != null && parentId != 'ROOT' && parentId.isNotEmpty) {
        request.fields['parent_id'] = parentId;
      }

      final streamedResponse = await request.send();
      final createResponse = await http.Response.fromStream(streamedResponse);

      if (createResponse.statusCode == 200 ||
          createResponse.statusCode == 201) {
        final data = jsonDecode(createResponse.body) as Map<String, dynamic>;
        return data['id'] as String?;
      }
    } catch (e) {
      debugPrint('VaultService: Error in getOrCreateFolderByName: $e');
    }
    return null;
  }

  Future<Either<Failure, Unit>> createFolder(String name) async {
    _isLoading = true;
    notifyListeners();

    final url = Uri.parse('${_config.backendUrl}/api/v1/mobile/vault/folders');

    final result = await callWithResilience<Unit>(
      call: () async {
        final request = http.MultipartRequest('POST', url)
          ..headers.addAll(authHeaders)
          ..fields['name'] = name
          ..fields['parent_id'] = currentParentId == 'ROOT'
              ? ''
              : currentParentId;

        final streamedResponse = await request.send();
        return await http.Response.fromStream(streamedResponse);
      },
      onSuccess: (_) async {
        await fetchDocuments();
        return unit;
      },
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Either<Failure, Unit>> updateDocumentMetadata(
    String docId, {
    String? newName,
    String? newType,
  }) async {
    _isLoading = true;
    notifyListeners();

    final url = Uri.parse('${_config.backendUrl}/api/v1/mobile/vault/$docId');

    final result = await callWithResilience<Unit>(
      call: () async {
        final request = http.MultipartRequest('PUT', url)
          ..headers.addAll(authHeaders);

        if (newName != null) request.fields['filename'] = newName;
        if (newType != null) request.fields['file_type'] = newType;

        final streamedResponse = await request.send();
        return await http.Response.fromStream(streamedResponse);
      },
      onSuccess: (_) async {
        await fetchDocuments();
        return unit;
      },
    );

    _isLoading = false;
    notifyListeners();
    return result;
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

  Future<Either<Failure, List<dynamic>>> searchTransactions({
    String? query,
    int limit = 20,
  }) async {
    final url = Uri.parse('${_config.backendUrl}/api/v1/mobile/transactions')
        .replace(
          queryParameters: {
            'limit': limit.toString(),
            if (query != null && query.isNotEmpty) 'search': query,
          },
        );

    return await callWithResilience<List<dynamic>>(
      call: () => http.get(url, headers: authHeaders),
      onSuccess: (body) => ((jsonDecode(body as String) as Map<String, dynamic>)['data'] as List<dynamic>?) ?? [],
    );
  }
}
