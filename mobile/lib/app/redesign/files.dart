part of '../online_prorab_redesign.dart';

class _FileUploadForm extends StatefulWidget {
  const _FileUploadForm({required this.projectId, required this.repository});

  final String projectId;
  final ProjectFileRepository repository;

  @override
  State<_FileUploadForm> createState() => _FileUploadFormState();
}

class _FileUploadFormState extends State<_FileUploadForm> {
  String _kind = 'receipt';
  PlatformFile? _selectedFile;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Добавить файл',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'Файл объекта',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Загрузите чек, фотографию или документ.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 22),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Тип файла'),
            items: const [
              DropdownMenuItem(value: 'receipt', child: Text('Чек')),
              DropdownMenuItem(value: 'photo', child: Text('Фото')),
              DropdownMenuItem(value: 'document', child: Text('Документ')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _kind = value ?? 'document'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(
              _selectedFile == null
                  ? 'Выбрать JPG, PNG, WEBP или PDF'
                  : _selectedFile!.name,
            ),
          ),
          if (_selectedFile != null) ...[
            const SizedBox(height: 8),
            Text(
              _fileSize(_selectedFile!.lengthSync() ?? 0),
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy || _selectedFile == null ? null : _upload,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_busy ? 'Загрузка…' : 'Загрузить'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      if (!mounted || result.isEmpty) return;
      final file = result.single;
      if (file.path == null || file.path!.isEmpty) {
        setState(() => _error = 'Выбранный файл недоступен.');
        return;
      }
      setState(() => _selectedFile = file);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось выбрать файл.');
    }
  }

  Future<void> _upload() async {
    final file = _selectedFile;
    final path = file?.path;
    if (file == null || path == null || path.isEmpty) {
      setState(() => _error = 'Сначала выберите файл.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uploaded = await widget.repository.upload(
        projectId: widget.projectId,
        kind: _kind,
        filePath: path,
        fileName: file.name,
      );
      if (mounted) Navigator.of(context).pop(uploaded);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
