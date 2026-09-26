import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 營養分析',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomePage(), 
    const Center(child: Text('這裡是紀錄頁面（準備放歷史資料，待開發）')),
    const SettingsPage(), 
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 營養分析')),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: '分析'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: '紀錄'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}

// ==========================================
// 1. 主頁面 (拍照與 AI 分析功能)
// ==========================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Uint8List? _imageBytes;
  final _noteController = TextEditingController();
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, maxWidth: 800);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _analyzeFood() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先拍攝或上傳一張圖片')));
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final prefs = await SharedPreferences.getInstance();
      // 使用 .trim() 確保讀取出來的 API Key 前後沒有不小心的空白或換行
      final apiKey = (prefs.getString('gemini_api_key') ?? '').trim();
      final modelName = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';

      if (apiKey.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先至「設定」頁面輸入 API Key')));
        setState(() { _isLoading = false; });
        return;
      }

      final base64Image = base64Encode(_imageBytes!);

      final prompt = '''
你是一位專業的營養師。請分析使用者上傳的食物照片，並參考其附加的文字備註：「${_noteController.text}」。
請估算圖中食物的總重量，並提供每 100 公克該食物的營養成分。
如果你無法判斷某個數值，請填寫 null。
必須嚴格依照以下 JSON 格式回傳，不要包含任何其他文字、解釋或 Markdown 標記 (例如 ```json)：
{
  "food_name": "判斷的食物名稱",
  "total_weight_g": 數字,
  "nutrients_per_100g": {
    "calories_kcal": 數字,
    "protein_g": 數字,
    "fat_g": 數字,
    "carbs_g": 數字,
    "dietary_fiber_g": 數字,
    "cholesterol_mg": 數字,
    "calcium_mg": 數字,
    "sodium_mg": 數字,
    "sugar_g": 數字
  }
}
'''; 

      // 使用 .trim() 確保整串網址前面不會有奇怪的符號導致解析錯誤
      final urlString = '[https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey'.trim](https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey'.trim)();
      final url = Uri.parse(urlString);
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [
              {"text": prompt},
              {
                "inline_data": {
                  "mime_type": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }],
          "generationConfig": {
            "response_mime_type": "application/json"
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final resultText = data['candidates'][0]['content']['parts'][0]['text'];
        
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('AI 分析結果'),
            content: SingleChildScrollView(child: Text(resultText)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))
            ],
          )
        );
      } else {
        if (!mounted) return;
        
        // 擷取 API 回傳的真實錯誤訊息
        String errorMessage = '未知錯誤';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error']['message'] ?? response.body;
        } catch (e) {
          errorMessage = response.body;
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('API 連線失敗 (狀態碼: ${response.statusCode})'),
            content: SingleChildScrollView(child: Text('錯誤訊息:\n$errorMessage')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('了解'))
            ],
          )
        );
      }

    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('App 發生錯誤'),
          content: SingleChildScrollView(child: Text(e.toString())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('了解'))
          ],
        )
      );
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: _imageBytes == null
                  ? const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('拍照'),
              ),
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('相簿'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: '文字備註 (例如：無糖、去冰)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit_note),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : _analyzeFood,
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text('送出 AI 分析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. 設定頁面 (儲存 Gemini API 金鑰)
// ==========================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyController = TextEditingController();
  String _selectedModel = 'gemini-3.8-flash';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      _selectedModel = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // 儲存前用 .trim() 去除使用者可能誤按的頭尾空白
    await prefs.setString('gemini_api_key', _apiKeyController.text.trim());
    await prefs.setString('gemini_model', _selectedModel);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('設定已儲存！')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gemini API 金鑰', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              hintText: '請輸入你的 API Key',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          const Text('選擇模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gemini-3.8-flash', child: Text('Gemini 3.8 Flash (最新推薦)')),
              DropdownMenuItem(value: 'gemini-3.7-flash', child: Text('Gemini 3.7 Flash')),
              DropdownMenuItem(value: 'gemini-3.5-flash-lite', child: Text('Gemini 3.5 Flash-Lite (輕量極速)')),
              DropdownMenuItem(value: 'gemini-3.1-pro-preview', child: Text('Gemini 3.1 Pro (高推理)')),
              DropdownMenuItem(value: 'gemini-3.8-live', child: Text('Gemini 3.8 Live (影音互動)')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedModel = value);
              }
            },
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              onPressed: _saveSettings,
              child: const Text('儲存設定', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
