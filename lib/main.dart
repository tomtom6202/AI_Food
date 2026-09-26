import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: false,
      ),
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

  final List<Widget> _pages = const [
    HomePage(),
    RecordsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'AI 食物分析' : _currentIndex == 1 ? '營養紀錄清單' : '設定'),
        backgroundColor: Colors.green,
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: '分析'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '紀錄'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}

// 營養素中文標籤對照表
final Map<String, String> nutrientDisplayNames = {
  'calories_kcal': '熱量 (kcal)',
  'protein_g': '蛋白質 (g)',
  'fat_g': '脂肪 (g)',
  'carbs_g': '碳水化合物 (g)',
  'dietary_fiber_g': '膳食纖維 (g)',
  'cholesterol_mg': '膽固醇 (mg)',
  'calcium_mg': '鈣 (mg)',
  'vitamin_A_ug': '維生素A (ug)',
  'vitamin_B1_mg': '維生素B1 (mg)',
  'vitamin_B2_mg': '維生素B2 (mg)',
  'vitamin_B6_mg': '維生素B6 (mg)',
  'vitamin_B12_ug': '維生素B12 (ug)',
  'vitamin_C_mg': '維生素C (mg)',
  'vitamin_D_ug': '維生素D (ug)',
  'vitamin_E_mg': '維生素E (mg)',
  'niacin_mg': '煙酸/尼克酸 (mg)',
  'phosphorus_mg': '磷 (mg)',
  'potassium_mg': '鉀 (mg)',
  'sodium_mg': '鈉 (mg)',
  'magnesium_mg': '鎂 (mg)',
  'iron_mg': '鐵 (mg)',
  'zinc_mg': '鋅 (mg)',
  'trans_fat_g': '反式脂肪 (g)',
  'saturated_fat_g': '飽和脂肪 (g)',
  'sugar_g': '糖 (g)',
  'selenium_ug': '硒 (ug)',
  'copper_ug': '銅 (ug)',
  'manganese_mg': '錳 (mg)',
};

// ==========================================
// 1. 主頁面 (拍照、備註與 AI 分析)
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先拍照或從相簿選取食物照片')));
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = (prefs.getString('gemini_api_key') ?? '').trim();
      // 這裡改回預設最新的 3.8 Flash
      final modelName = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';

      if (apiKey.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先切換至「設定」頁面輸入 API Key')));
        setState(() { _isLoading = false; });
        return;
      }

      final base64Image = base64Encode(_imageBytes!);

      final prompt = '''
你是一位專業營養師。請分析照片中的食物，並參考備註：「${_noteController.text.trim()}」。
請估算該食物總重量（公克），並給出每 100g 該食物的營養數值。

【必須遵守的規則】
1. 只輸出純 JSON 物件，嚴禁包含 Markdown 標籤或任何其他說明文字。
2. 以下 4 項為必填數值：calories_kcal, protein_g, fat_g, carbs_g。
3. 其他營養素若含有請提供數值，若無或無法估算請填 null：
dietary_fiber_g, cholesterol_mg, calcium_mg, vitamin_A_ug, vitamin_B1_mg, vitamin_B2_mg, vitamin_B6_mg, vitamin_B12_ug, vitamin_C_mg, vitamin_D_ug, vitamin_E_mg, niacin_mg, phosphorus_mg, potassium_mg, sodium_mg, magnesium_mg, iron_mg, zinc_mg, trans_fat_g, saturated_fat_g, sugar_g, selenium_ug, copper_ug, manganese_mg。

JSON 結構範例：
{
  "food_name": "估計的食物名稱",
  "total_weight_g": 200,
  "nutrients_per_100g": {
    "calories_kcal": 150,
    "protein_g": 10.0,
    "fat_g": 5.0,
    "carbs_g": 15.0,
    "dietary_fiber_g": null
  }
}
''';

      final String protocol = 'https://';
      final String host = 'generativelanguage.googleapis.com';
      final String path = '/v1beta/models/$modelName:generateContent?key=$apiKey';
      final String cleanUrl = protocol + host + path;
      
      final url = Uri.parse(cleanUrl);

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
                {
                  "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": base64Image
                  }
                }
              ]
            }
          ],
          "generationConfig": {
            "response_mime_type": "application/json"
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String rawText = data['candidates'][0]['content']['parts'][0]['text'];
        
        int startIndex = rawText.indexOf('{');
        int endIndex = rawText.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1) {
          rawText = rawText.substring(startIndex, endIndex + 1);
        }

        final Map<String, dynamic> resultJson = jsonDecode(rawText);

        if (!mounted) return;
        _showResultAndSaveDialog(resultJson);
      } else {
        String msg = '未知錯誤';
        try {
          final errorData = jsonDecode(response.body);
          msg = errorData['error']['message'] ?? response.body;
        } catch (_) {
          msg = response.body;
        }

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('API 連線失敗 (${response.statusCode})'),
            content: SingleChildScrollView(child: Text('伺服器訊息:\n$msg')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('分析過程發生錯誤'),
          content: SingleChildScrollView(child: Text(e.toString())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))
          ],
        ),
      );
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  void _showResultAndSaveDialog(Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: data['food_name'] ?? '未命名食物');
    final totalWeight = data['total_weight_g'] ?? 0;
    final Map<String, dynamic> nutrients = data['nutrients_per_100g'] ?? {};

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 分析完成'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '食物名稱 (可自由修改)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text('預估總重量: $totalWeight 公克', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(height: 20),
                const Text('每 100g 營養含量：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...nutrients.entries.where((e) => e.value != null).map((e) {
                  final label = nutrientDisplayNames[e.key] ?? e.key;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label),
                        Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('捨棄'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              data['food_name'] = nameCtrl.text.trim();
              data['record_date'] = DateTime.now().toString().substring(0, 16);

              final prefs = await SharedPreferences.getInstance();
              final raw = prefs.getString('food_records') ?? '[]';
              final List list = jsonDecode(raw);
              list.insert(0, data);
              await prefs.setString('food_records', jsonEncode(list));

              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已儲存至「紀錄」頁面！')));
            },
            child: const Text('儲存紀錄', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
                  ? const Center(child: Text('請點選下方按鈕拍照或上傳照片', style: TextStyle(color: Colors.grey)))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('拍照'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('相簿'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: '文字備註 (例如：無糖、半份、去皮)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit_note),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
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
// 2. 紀錄頁面 (檢視、編輯名稱、匯出/上傳 JSON)
// ==========================================
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('food_records') ?? '[]';
    final List decoded = jsonDecode(raw);
    setState(() {
      _records = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    });
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('food_records', jsonEncode(_records));
  }

  void _exportJson() {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_records);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('匯出紀錄 (JSON)'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(jsonStr),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已複製 JSON 至剪貼簿！')));
            },
            child: const Text('複製全部'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        ],
      ),
    );
  }

  void _importJson() {
    final inputCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上傳 / 匯入紀錄'),
        content: TextField(
          controller: inputCtrl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '請貼上先前匯出的 JSON 陣列資料...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                final List parsed = jsonDecode(inputCtrl.text.trim());
                setState(() {
                  _records = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
                });
                await _saveRecords();
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('匯入成功！')));
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 格式有誤，無法解析')));
              }
            },
            child: const Text('確定匯入'),
          ),
        ],
      ),
    );
  }

  void _showDetail(Map<String, dynamic> item, int index) {
    final Map<String, dynamic> nutrients = item['nutrients_per_100g'] ?? {};
    final editCtrl = TextEditingController(text: item['food_name']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(item['food_name'] ?? '詳細數據')),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (editCtx) => AlertDialog(
                    title: const Text('修改名稱'),
                    content: TextField(controller: editCtrl),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(editCtx), child: const Text('取消')),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            item['food_name'] = editCtrl.text.trim();
                          });
                          _saveRecords();
                          Navigator.pop(editCtx);
                          Navigator.pop(ctx);
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('紀錄時間: ${item['record_date'] ?? '無'}'),
                Text('預估總重: ${item['total_weight_g'] ?? 0} 公克', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                const Text('每 100g 數值：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...nutrients.entries.where((e) => e.value != null).map((e) {
                  final label = nutrientDisplayNames[e.key] ?? e.key;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label),
                        Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _records.removeAt(index);
              });
              _saveRecords();
              Navigator.pop(ctx);
            },
            child: const Text('刪除此筆'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: _exportJson,
                icon: const Icon(Icons.file_download),
                label: const Text('匯出紀錄'),
              ),
              OutlinedButton.icon(
                onPressed: _importJson,
                icon: const Icon(Icons.file_upload),
                label: const Text('上傳紀錄'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _records.isEmpty
              ? const Center(child: Text('目前尚無分析紀錄'))
              : ListView.builder(
                  itemCount: _records.length,
                  itemBuilder: (ctx, i) {
                    final item = _records[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.green,
                        child: Icon(Icons.restaurant, color: Colors.white),
                      ),
                      title: Text(item['food_name'] ?? '未命名食物', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item['record_date'] ?? ''} · 約 ${item['total_weight_g'] ?? 0}g'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showDetail(item, i),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ==========================================
// 3. 設定頁面 (儲存 API Key 與模型選擇)
// ==========================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyController = TextEditingController();
  // 將初始預設值改為最新的 3.8 Flash
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
    await prefs.setString('gemini_api_key', _apiKeyController.text.trim());
    await prefs.setString('gemini_model', _selectedModel);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('設定已成功儲存！')),
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
              hintText: '請輸入你的 Gemini API Key',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          const Text('選擇模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            // 替換回最新的 2026 模型清單
            items: const [
              DropdownMenuItem(value: 'gemini-3.8-flash', child: Text('Gemini 3.8 Flash (最新推薦)')),
              DropdownMenuItem(value: 'gemini-3.7-flash', child: Text('Gemini 3.7 Flash')),
              DropdownMenuItem(value: 'gemini-3.5-flash-lite', child: Text('Gemini 3.5 Flash-Lite (輕量極速)')),
              DropdownMenuItem(value: 'gemini-3.1-pro-preview', child: Text('Gemini 3.1 Pro (高推理)')),
              DropdownMenuItem(value: 'gemini-3.8-live', child: Text('Gemini 3.8 Live (影音互動)')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedModel = val);
              }
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
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
