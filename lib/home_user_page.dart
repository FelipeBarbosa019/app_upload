import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomeUserPage extends StatefulWidget {
  const HomeUserPage({super.key});

  @override
  State<HomeUserPage> createState() => _HomeUserPageState();
}

class _HomeUserPageState extends State<HomeUserPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _documents = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado');
      }
      final userId = user.id;

      final response = await Supabase.instance.client
          .from('documents')
          .select()
          .eq('user_id', userId);

      if (response.isEmpty) {
        throw Exception('Nenhum documento encontrado');
      }

      setState(() {
        _documents = response.map((doc) {
          return {
            'id': doc['id'],
            'name': doc['file_name'],
            'url': doc['file_url'],
            'isImage': _isImageFile(doc['file_name']),
            'size': doc['size'],
            'type': doc['file_type'],
          };
        }).toList();

        context.read<DocumentTabController>().updateHasDocuments(_documents);
      });
    } catch (e) {
      print('Erro ao carregar documentos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar documentos: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isImageFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif';
  }

  Future<void> _uploadFile(
      String tabTitle, File fileToUpload, String fileName) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final uploadResponse = await Supabase.instance.client.storage
          .from('uploads')
          .upload(fileName, fileToUpload);

      print('Arquivo enviado com sucesso: $uploadResponse');

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado');
      }
      final userId = user.id;

      final fileUrl = Supabase.instance.client.storage
          .from('uploads')
          .getPublicUrl(fileName);

      await Supabase.instance.client.from('documents').insert([
        {
          'user_id': userId,
          'file_name': fileName,
          'file_url': fileUrl,
          'file_type': tabTitle.toLowerCase(),
          'size': fileToUpload.lengthSync(),
          'created_at': DateTime.now().toIso8601String(),
        }
      ]);

      _loadDocuments();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arquivo $fileName enviado com sucesso!')),
      );
    } catch (e) {
      print('Erro durante o upload: $e');

      if (fileName.isNotEmpty) {
        try {
          await Supabase.instance.client.storage
              .from('uploads')
              .remove([fileName]);
          print(
              'Arquivo $fileName removido do Supabase Storage devido a erro.');
        } catch (deleteError) {
          print('Erro ao remover arquivo do Supabase Storage: $deleteError');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar arquivo: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _takePhoto(String tabTitle) async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo != null) {
        final fileToUpload = File(photo.path);
        final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

        await _uploadFile(tabTitle, fileToUpload, fileName);
      }
    } catch (e) {
      print('Erro ao capturar foto: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao capturar foto: $e')),
      );
    }
  }

  Future<void> _checkAndRequestPermissions(String tabTitle) async {
    Permission permission;

    if (Platform.isAndroid) {
      var androidInfo = await DeviceInfoPlugin().androidInfo;
      int sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 30) {
        permission = Permission.manageExternalStorage;
      } else {
        permission = Permission.storage;
      }
    } else {
      permission = Permission.storage;
    }

    var status = await permission.status;

    if (!status.isGranted) {
      status = await permission.request();
    }

    if (status.isGranted) {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        final file = result.files.single;
        final fileName = file.name;
        final filePath = file.path;

        if (filePath != null) {
          final fileToUpload = File(filePath);
          await _uploadFile(tabTitle, fileToUpload, fileName);
        }
      }
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissão para acessar o armazenamento foi negada.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabController = context.watch<DocumentTabController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDocuments,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: ExpansionPanelList(
                expansionCallback: (int index, bool isExpanded) {
                  tabController.toggleExpansion(index);
                },
                children:
                    tabController.tabs.map<ExpansionPanel>((DocumentTab tab) {
                  return ExpansionPanel(
                    backgroundColor:
                        tab.hasDocuments ? Colors.green[100] : Colors.yellow[0],
                    headerBuilder: (BuildContext context, bool isExpanded) {
                      return Container(
                        color: tab.hasDocuments
                            ? Colors.green[100]
                            : Colors.yellow[0],
                        child: ListTile(
                          title: Text(tab.title),
                          tileColor: Colors.transparent,
                        ),
                      );
                    },
                    body: Column(
                      children: [
                        if (_documents.any(
                            (doc) => doc['type'] == tab.title.toLowerCase()))
                          ..._documents
                              .where((doc) =>
                                  doc['type'] == tab.title.toLowerCase())
                              .map((doc) => _buildDocumentListItem(doc))
                              .toList(),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                onPressed: () =>
                                    _checkAndRequestPermissions(tab.title),
                                child: const Text('Fazer Upload'),
                              ),
                              ElevatedButton(
                                onPressed: () => _takePhoto(tab.title),
                                child: const Text('Tirar Foto'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    isExpanded: tab.isExpanded,
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildDocumentListItem(Map<String, dynamic> document) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
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
        title: Text(document['name']),
        subtitle: Text('Tipo: ${document['type'] ?? 'Desconhecido'}'),
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
              _renameFile(document['name'], document['id']);
            } else if (value == 'delete') {
              _deleteFile(document['name'], document['id']);
            }
          },
        ),
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tamanho: ${_formatFileSize(document['size'] ?? 0)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(String fileName, String documentId) async {
    try {
      setState(() {
        _isLoading = true;
      });

      await Supabase.instance.client.storage.from('uploads').remove([fileName]);

      await Supabase.instance.client
          .from('documents')
          .delete()
          .eq('id', documentId);

      await _loadDocuments();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arquivo $fileName excluído com sucesso!')),
      );
    } catch (e) {
      print('Erro ao excluir arquivo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir arquivo: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _renameFile(String oldName, String documentId) async {
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

        await Supabase.instance.client
            .from('documents')
            .update({'file_name': newName}).eq('id', documentId);

        await _loadDocuments();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arquivo renomeado para $newName!')),
        );
      } catch (e) {
        print('Erro ao renomear arquivo: $e');
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

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      print('Baixando arquivo: $fileName');
      print('URL: $url');
    } catch (e) {
      print('Erro ao baixar arquivo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao baixar arquivo: $e')),
      );
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

class DocumentTab {
  final String title;
  bool isExpanded;
  bool hasDocuments;

  DocumentTab({
    required this.title,
    this.isExpanded = false,
    this.hasDocuments = false,
  });
}

class DocumentTabController extends ChangeNotifier {
  List<DocumentTab> _tabs = [
    DocumentTab(title: 'Trabalhadores Fixos e Temporários'),
    DocumentTab(title: 'Holerites dos Últimos 3 Meses'),
    DocumentTab(title: 'Exames Médicos ASO'),
    DocumentTab(title: 'PCMSO, PGRTR e LTCAT'),
    DocumentTab(title: 'Ficha de Entrega e Controle de Lavagem de EPIs'),
    DocumentTab(title: 'Folha de Ponto'),
    DocumentTab(title: 'Guia de Recolhimento de FGTS e INSS'),
    DocumentTab(title: 'Cópia do Acordo de Convenção Coletiva'),
    DocumentTab(title: 'Contratos de Trabalho'),
  ];

  List<DocumentTab> get tabs => _tabs;

  void toggleExpansion(int index) {
    _tabs[index].isExpanded = !_tabs[index].isExpanded;
    notifyListeners();
  }

  void updateHasDocuments(List<Map<String, dynamic>> documents) {
    for (var tab in _tabs) {
      tab.hasDocuments =
          documents.any((doc) => doc['type'] == tab.title.toLowerCase());
    }
    notifyListeners();
  }
}
