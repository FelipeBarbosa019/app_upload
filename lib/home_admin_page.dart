import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class HomeAdminPage extends StatefulWidget {
  const HomeAdminPage({super.key});

  @override
  State<HomeAdminPage> createState() => _HomeAdminPageState();
}

class _HomeAdminPageState extends State<HomeAdminPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _profiles = [];
  Map<String, List<Map<String, dynamic>>> _groupedDocuments = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, user_name, tax_id');

      _profiles = List<Map<String, dynamic>>.from(profilesResponse);
      _groupedDocuments = {};

      for (var profile in _profiles) {
        _groupedDocuments[profile['id']] = [];
      }
    } catch (e) {
      print('***** Erro ao carregar perfis: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDocumentsForUser(String userId) async {
    try {
      final documentsResponse = await Supabase.instance.client
          .from('documents')
          .select('user_id, file_name, file_type, size')
          .eq('user_id', userId);

      setState(() {
        _groupedDocuments[userId] = [];

        for (var file in documentsResponse) {
          _groupedDocuments[userId]!.add({
            'name': file['file_name'],
            'url': Supabase.instance.client.storage
                .from('uploads')
                .getPublicUrl(file['file_name']),
            'isImage': _isImageFile(file['file_name']),
            'size': file['size'],
            'type': _getFileType(file['file_name']),
            'user_id': userId,
          });
        }
      });
    } catch (e) {
      print('***** Erro ao carregar documentos: $e');
    }
  }

  List<Map<String, dynamic>> _filterProfiles(String query) {
    if (query.isEmpty) {
      return _profiles;
    }
    return _profiles.where((profile) {
      final userName = profile['user_name'].toString().toLowerCase();
      final taxId = profile['tax_id']
          .toString()
          .replaceAll(RegExp(r'[.\-]'), '')
          .toLowerCase();
      final searchQuery = query.replaceAll(RegExp(r'[.\-]'), '').toLowerCase();

      return userName.contains(searchQuery) || taxId.contains(searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredProfiles = _filterProfiles(_searchQuery);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProfiles,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Pesquisar por nome ou CPF...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredProfiles.isEmpty
              ? const Center(child: Text('Nenhum perfil encontrado.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filteredProfiles.length,
                  itemBuilder: (context, index) {
                    final profile = filteredProfiles[index];
                    final userId = profile['id'];
                    final documents = _groupedDocuments[userId] ?? [];
                    return _buildProfileExpansionTile(profile, documents);
                  },
                ),
    );
  }

  Widget _buildProfileExpansionTile(
      Map<String, dynamic> profile, List<Map<String, dynamic>> documents) {
    return ExpansionTile(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile['user_name']),
          Text(
            'CPF: ${profile['tax_id']}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
      children: documents.isEmpty
          ? [const ListTile(title: Text('Nenhum documento encontrado.'))]
          : documents
              .map((document) => _buildDocumentListItem(document))
              .toList(),
      onExpansionChanged: (isExpanded) {
        if (isExpanded && documents.isEmpty) {
          _loadDocumentsForUser(profile['id']);
        }
      },
    );
  }

  Widget _buildDocumentListItem(Map<String, dynamic> document) {
    return ListTile(
      leading: document['isImage']
          ? CachedNetworkImage(
              imageUrl: document['url'],
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(),
              ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            )
          : const Icon(Icons.insert_drive_file, size: 50),
      subtitle: Text(
          'Nome do documento: ${document['name'] ?? 'Sem nome'}\nTipo: ${document['type'] ?? 'Desconhecido'}\nTamanho: ${_formatFileSize(document['size'] ?? 0)}'),
      trailing: PopupMenuButton(
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'download',
            child: Text('Baixar'),
          ),
          const PopupMenuItem(
            value: 'rename',
            child: Text('Renomear'),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Excluir'),
          ),
        ],
        onSelected: (value) {
          if (value == 'download') {
            _downloadFile(document['url'], document['name']);
          } else if (value == 'rename') {
            _renameFile(document['name']);
          } else if (value == 'delete') {
            _deleteFile(document['name']);
          }
        },
      ),
    );
  }

  bool _isImageFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif';
  }

  Future<void> _uploadFile() async {
    try {
      setState(() {
        _isLoading = true;
      });

      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        final file = result.files.single;
        final fileName = file.name;
        final filePath = file.path;

        if (filePath != null) {
          final fileToUpload = File(filePath);

          await Supabase.instance.client.storage
              .from('uploads')
              .upload(fileName, fileToUpload);

          await _loadProfiles();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Arquivo $fileName enviado com sucesso!')),
          );

          await fileToUpload.delete();
        }
      }
    } catch (e) {
      print('***** Erro durante o upload: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar arquivo: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteFile(String fileName) async {
    try {
      setState(() {
        _isLoading = true;
      });

      await Supabase.instance.client.storage.from('uploads').remove([fileName]);

      await _loadProfiles();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arquivo $fileName excluído com sucesso!')),
      );
    } catch (e) {
      print('***** Erro ao excluir arquivo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir arquivo: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      print('***** Baixando arquivo: $fileName');
      print('***** URL: $url');
    } catch (e) {
      print('***** Erro ao baixar arquivo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao baixar arquivo: $e')),
      );
    }
  }

  Future<void> _renameFile(String oldName) async {
    final newNameController = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Alterar nome do arquivo'),
          content: TextField(
            controller: newNameController,
            decoration: const InputDecoration(hintText: 'Novo nome do arquivo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, newNameController.text),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty) {
      try {
        setState(() {
          _isLoading = true;
        });

        await Supabase.instance.client.storage
            .from('uploads')
            .move(oldName, newName);

        await _loadProfiles();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arquivo renomeado para $newName!')),
        );
      } catch (e) {
        print('***** Erro ao renomear arquivo: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao renomear arquivo: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return 'Imagem';
      case 'pdf':
        return 'PDF';
      case 'doc':
      case 'docx':
        return 'Documento Word';
      case 'xls':
      case 'xlsx':
        return 'Planilha Excel';
      case 'txt':
        return 'Texto';
      case 'zip':
      case 'rar':
        return 'Arquivo Compactado';
      default:
        return 'Arquivo';
    }
  }

  String _formatFileSize(dynamic size) {
    final int fileSize =
        size is int ? size : int.tryParse(size.toString()) ?? 0;
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1048576) {
      return '${(fileSize / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(fileSize / 1048576).toStringAsFixed(2)} MB';
    }
  }
}
