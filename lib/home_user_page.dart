import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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
    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final response = await Supabase.instance.client
          .from('documents')
          .select()
          .eq('user_id', user.id);

      if (response.isEmpty) throw Exception('Nenhum documento encontrado');

      setState(() {
        _documents = response
            .map((doc) => {
                  'id': doc['id'],
                  'name': doc['file_name'],
                  'url': doc['file_url'],
                  'isImage': _isImageFile(doc['file_name']),
                  'size': doc['size'],
                  'type': doc['file_type'],
                })
            .toList();

        context.read<DocumentTabController>().updateHasDocuments(_documents);
      });
    } catch (e) {
      print('Erro ao carregar documentos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar documentos: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isImageFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif'].contains(ext);
  }

  Future<void> _uploadFile(
      String tabTitle, File fileToUpload, String fileName) async {
    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.storage
          .from('uploads')
          .upload(fileName, fileToUpload);

      final fileUrl = Supabase.instance.client.storage
          .from('uploads')
          .getPublicUrl(fileName);

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      await Supabase.instance.client.from('documents').insert([
        {
          'user_id': user.id,
          'file_name': fileName,
          'file_url': fileUrl,
          'file_type': tabTitle.toLowerCase(),
          'size': fileToUpload.lengthSync(),
          'created_at': DateTime.now().toIso8601String(),
        }
      ]);

      await _loadDocuments();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arquivo $fileName enviado com sucesso!')),
      );
    } catch (e) {
      print('Erro durante o upload: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar arquivo: $e')),
      );

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
    } finally {
      setState(() => _isLoading = false);
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
    Permission permission = Platform.isAndroid &&
            (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 30
        ? Permission.manageExternalStorage
        : Permission.storage;

    var status = await permission.status;
    if (!status.isGranted) status = await permission.request();

    if (status.isGranted) {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        await _uploadFile(tabTitle, File(file.path!), file.name);
      }
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Permissão para acessar o armazenamento foi negada.')),
      );
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      Directory? dir;

      if (Platform.isAndroid) {
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('Permissão de armazenamento negada.');
        }
        dir = Directory('/storage/emulated/0/Download');
      } else if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      }

      if (dir == null)
        throw Exception('Diretório de armazenamento não encontrado.');

      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            print('Progresso: ${(received / total * 100).toStringAsFixed(0)}%');
          }
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Arquivo $fileName baixado com sucesso!\nLocal: $filePath')),
      );
    } catch (e) {
      print('Erro ao baixar arquivo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao baixar arquivo: $e')),
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
                      return ListTile(
                        title: Text(tab.title),
                        tileColor: Colors.transparent,
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
              value: 'delete',
              child: Text('Excluir'),
            ),
          ],
          onSelected: (value) {
            if (value == 'download') {
              _downloadFile(document['url'], document['name']);
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
    setState(() => _isLoading = true);

    try {
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
      setState(() => _isLoading = false);
    }
  }

  String _formatFileSize(dynamic size) {
    final int fileSize =
        size is int ? size : int.tryParse(size.toString()) ?? 0;
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1048576) return '${(fileSize / 1024).toStringAsFixed(2)} KB';
    return '${(fileSize / 1048576).toStringAsFixed(2)} MB';
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
  final List<DocumentTab> _tabs = [
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
