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
      final modelName = prefs.getString('gemini_model') ?? 'gemini-1.5-flash-8b';

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
1. 只輸出純 JSON 物件，嚴禁包含 Markdown 標籤 (```json) 或任何其他說明文字。
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

      // 這裡已經修復了被自動轉成 Markdown 連結的問題
      final cleanUrl = '[https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey'.trim](https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey'.trim)();
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
        
        rawText = rawText.replaceAll('
