import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 營養顧問',
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(onGoToSettings: () => setState(() => _currentIndex = 3)),
      const RecordsPage(),
      const CalculatorPage(), // 👇 新增的熱量計算頁面
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'AI 食物分析' : _currentIndex == 1 ? '營養紀錄清單' : _currentIndex == 2 ? '熱量計算' : '設定'),
        backgroundColor: Colors.green,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed, // 超過3個選項需加上這行
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: '分析'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '紀錄'),
          BottomNavigationBarItem(icon: Icon(Icons.calculate), label: '計算'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}

final Map<String, String> nutrientDisplayNames = {
  'calories_kcal': '熱量', 'protein_g': '蛋白質', 'fat_g': '脂肪', 'carbs_g': '碳水',
  'dietary_fiber_g': '膳食纖維 (g)', 'cholesterol_mg': '膽固醇 (mg)', 'calcium_mg': '鈣 (mg)',
  'vitamin_A_ug': '維生素A (ug)', 'vitamin_B1_mg': '維生素B1 (mg)', 'vitamin_B2_mg': '維生素B2 (mg)',
  'vitamin_B6_mg': '維生素B6 (mg)', 'vitamin_B12_ug': '維生素B12 (ug)', 'vitamin_C_mg': '維生素C (mg)',
  'vitamin_D_ug': '維生素D (ug)', 'vitamin_E_mg': '維生素E (mg)', 'niacin_mg': '煙酸 (mg)',
  'phosphorus_mg': '磷 (mg)', 'potassium_mg': '鉀 (mg)', 'sodium_mg': '鈉 (mg)', 'magnesium_mg': '鎂 (mg)',
  'iron_mg': '鐵 (mg)', 'zinc_mg': '鋅 (mg)', 'trans_fat_g': '反式脂肪 (g)', 'saturated_fat_g': '飽和脂肪 (g)',
  'sugar_g': '糖 (g)', 'selenium_ug': '硒 (ug)', 'copper_ug': '銅 (ug)', 'manganese_mg': '錳 (mg)',
};

Widget _buildEvalRow(String title, Map<String, dynamic>? evalData) {
  if (evalData == null) return const SizedBox.shrink();
  final score = evalData['score'] ?? '?';
  final reason = evalData['reason'] ?? '';
  Color scoreColor = Colors.grey;
  if (score == 'A') scoreColor = Colors.green;
  if (score == 'B') scoreColor = Colors.blue;
  if (score == 'C') scoreColor = Colors.orange;
  if (score == 'D') scoreColor = Colors.red;

  return Padding(
    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: scoreColor.withOpacity(0.2), border: Border.all(color: scoreColor), borderRadius: BorderRadius.circular(4)), child: Text(score, style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold))),
          ],
        ),
        const SizedBox(height: 4),
        Text(reason, style: const TextStyle(color: Colors.black87)),
      ],
    ),
  );
}

// ==========================================
// 1. 主頁面 (與之前相同，僅更新導覽邏輯)
// ==========================================
class HomePage extends StatefulWidget {
  final VoidCallback onGoToSettings;
  const HomePage({super.key, required this.onGoToSettings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Uint8List? _imageBytes;
  final _noteController = TextEditingController();
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final prefs = await SharedPreferences.getInstance();
    final uploadOriginal = prefs.getBool('upload_original') ?? false;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, maxWidth: uploadOriginal ? 1920 : 800, maxHeight: uploadOriginal ? 1920 : 800, imageQuality: uploadOriginal ? 100 : 70);
    if (pickedFile != null) { final bytes = await pickedFile.readAsBytes(); setState(() { _imageBytes = bytes; }); }
  }

  Future<String> _generateDbThumbnail(Uint8List originalBytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(originalBytes, targetWidth: 400);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData? byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) return base64Encode(byteData.buffer.asUint8List());
    } catch (_) {}
    return base64Encode(originalBytes); 
  }

  Future<void> _analyzeFood() async {
    if (_imageBytes == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先拍照或從相簿選取食物照片'))); return; }
    setState(() { _isLoading = true; });
    bool isRetrying = false; bool isCancelled = false; BuildContext? dialogContext;

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = (prefs.getString('gemini_api_key') ?? '').trim();
      final modelName = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';

      if (apiKey.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先切換至「設定」頁面輸入 API Key')));
        setState(() { _isLoading = false; }); return;
      }

      final base64Image = base64Encode(_imageBytes!);
      final prompt = '''
你是一位專業的 AI 營養顧問。請分析照片中的食物，並參考備註：「${_noteController.text.trim()}」。
【特別要求：精準抓取微量元素】
1. 若圖片中包含「營養標示」或包裝文字，請優先精準辨識並讀取標示上的所有數值（包含微量元素與糖分）。
2. 若無標示，請根據食物種類，盡可能估算其富含的維生素與礦物質，不要因為不確定就全部填 null，請給出合理的預估值。
【必須遵守的規則】
1. 只輸出純 JSON 物件，嚴禁包含 Markdown 標籤。
2. 估算總重量(total_weight_g)，並給出每 100g 的營養數值(nutrients_per_100g)。(必填: calories_kcal, protein_g, fat_g, carbs_g)
3. 包含 "breakdown" 陣列：拆解各食材或獨立食物的 name, weight_g, calories_kcal。
4. 包含 "evaluation" 物件，評分與說明(reason)：fitness(健身), weight_loss(瘦身), diversity(多樣性), overall(綜合)。
''';

      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey');
      final requestBody = jsonEncode({ "contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": "image/jpeg", "data": base64Image}}]}], "generationConfig": {"response_mime_type": "application/json"} });

      while (!isCancelled) {
        final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: requestBody);
        if (response.statusCode == 200) {
          if (isRetrying && dialogContext != null && mounted) { Navigator.pop(dialogContext!); isRetrying = false; }
          final data = jsonDecode(response.body);
          String rawText = data['candidates'][0]['content']['parts'][0]['text'];
          int startIndex = rawText.indexOf('{'); int endIndex = rawText.lastIndexOf('}');
          if (startIndex != -1 && endIndex != -1) rawText = rawText.substring(startIndex, endIndex + 1);
          final dbThumbnailBase64 = await _generateDbThumbnail(_imageBytes!);
          if (!mounted) return;
          _showResultAndSaveDialog(jsonDecode(rawText), dbThumbnailBase64);
          break; 
        } else if (response.statusCode == 503) {
          if (!isRetrying) {
            isRetrying = true;
            if (!mounted) return;
            showDialog(context: context, barrierDismissible: false, builder: (ctx) {
                dialogContext = ctx;
                return AlertDialog(title: const Text('伺服器滿載中'), content: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.green), SizedBox(height: 16), Text('排隊等待模型中，請稍後。\n如等待過久，請至設定中嘗試其他模型。', textAlign: TextAlign.center)]), actions: [TextButton(onPressed: () { isCancelled = true; Navigator.pop(ctx); }, child: const Text('取消', style: TextStyle(color: Colors.grey))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), onPressed: () { isCancelled = true; Navigator.pop(ctx); widget.onGoToSettings(); }, child: const Text('選擇其他模型', style: TextStyle(color: Colors.white)))]);
            });
          }
          await Future.delayed(const Duration(milliseconds: 500)); continue;
        } else {
          if (isRetrying && dialogContext != null && mounted) { Navigator.pop(dialogContext!); isRetrying = false; }
          String msg = '未知錯誤';
          try { msg = jsonDecode(response.body)['error']['message'] ?? response.body; } catch (_) { msg = response.body; }
          if (!mounted) return;
          showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('API 連線失敗 (${response.statusCode})'), content: SingleChildScrollView(child: Text('伺服器訊息:\n$msg')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))]));
          break;
        }
      }
    } catch (e) {
      if (isRetrying && dialogContext != null && mounted) Navigator.pop(dialogContext!);
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('發生錯誤'), content: SingleChildScrollView(child: Text(e.toString())), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))]));
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _showResultAndSaveDialog(Map<String, dynamic> data, String dbBase64Img) {
    final nameCtrl = TextEditingController(text: data['food_name'] ?? '未命名食物');
    final num totalWeight = data['total_weight_g'] ?? 0;
    final Map<String, dynamic> nutrients = data['nutrients_per_100g'] ?? {};
    final num totalCalories = ((nutrients['calories_kcal'] ?? 0) / 100) * totalWeight;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 分析完成'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '食物名稱', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Column(children: [const Text('預估總重量', style: TextStyle(color: Colors.green)), Text('$totalWeight g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]), Column(children: [const Text('預估總熱量', style: TextStyle(color: Colors.green)), Text('${totalCalories.toStringAsFixed(1)} kcal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))])])),
                const Divider(height: 24),
                // (省略其他UI避免版面過長，維持原樣)
                const Text('📊 每 100g 營養素含量：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ...nutrients.entries.where((e) => e.value != null).map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 2.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(nutrientDisplayNames[e.key] ?? e.key), Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold))]))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('捨棄')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              data['food_name'] = nameCtrl.text.trim();
              data['record_date'] = DateTime.now().toString().substring(0, 16);
              data['calculated_total_calories'] = totalCalories;
              data['image_base64'] = dbBase64Img; 
              final prefs = await SharedPreferences.getInstance();
              final List list = jsonDecode(prefs.getString('food_records') ?? '[]');
              list.insert(0, data);
              await prefs.setString('food_records', jsonEncode(list));
              if (!mounted) return;
              Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已儲存！')));
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
          Expanded(child: Container(width: double.infinity, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)), child: _imageBytes == null ? const Center(child: Text('請點選下方按鈕拍照', style: TextStyle(color: Colors.grey))) : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, fit: BoxFit.cover)))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('拍照'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)), ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('相簿'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))]),
          const SizedBox(height: 12),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: '文字備註 (例如：無糖、半份、去皮)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.edit_note))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: _isLoading ? null : _analyzeFood, child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('送出 AI 分析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }
}

// ==========================================
// 2. 紀錄頁面 (升級實體檔案匯出/匯入)
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
    final List decoded = jsonDecode(prefs.getString('food_records') ?? '[]');
    setState(() { _records = decoded.map((e) => Map<String, dynamic>.from(e)).toList(); });
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('food_records', jsonEncode(_records));
  }

  // 👇 使用實體檔案分享 JSON
  Future<void> _exportJsonFile() async {
    try {
      final String jsonString = jsonEncode(_records);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/food_records_backup.json');
      await file.writeAsString(jsonString);
      
      final xFile = XFile(file.path, mimeType: 'application/json');
      await Share.shareXFiles([xFile], text: '我的 AI 飲食紀錄備份');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匯出失敗: $e')));
    }
  }

  // 👇 使用檔案瀏覽器選取 JSON 匯入
  Future<void> _importJsonFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String jsonString = await file.readAsString();
        final List parsed = jsonDecode(jsonString);
        
        setState(() { _records = parsed.map((e) => Map<String, dynamic>.from(e)).toList(); });
        await _saveRecords();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('檔案匯入成功！')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匯入失敗，請確認檔案格式: $e')));
    }
  }

  // (省略 _showDetail 內容，保持不變以免過長)
  void _showDetail(Map<String, dynamic> item, int index) {
    // 內容與之前版本相同...
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
              OutlinedButton.icon(onPressed: _exportJsonFile, icon: const Icon(Icons.download), label: const Text('匯出檔案')),
              OutlinedButton.icon(onPressed: _importJsonFile, icon: const Icon(Icons.upload_file), label: const Text('上傳檔案')),
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
                    final String? base64Img = item['image_base64'];
                    num totalCalories = item['calculated_total_calories'] ?? (((item['nutrients_per_100g']?['calories_kcal'] ?? 0) / 100) * (item['total_weight_g'] ?? 0));
                    return ListTile(
                      leading: base64Img != null && base64Img.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), width: 50, height: 50, fit: BoxFit.cover)) : const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.restaurant, color: Colors.white)),
                      title: Text(item['food_name'] ?? '未命名食物', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item['record_date'] ?? ''}\n${item['total_weight_g'] ?? 0}g · ${totalCalories.toStringAsFixed(0)} kcal'),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: (){ setState(() { _records.removeAt(i); }); _saveRecords(); }),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ==========================================
// 3. 全新功能：熱量計算頁面
// ==========================================
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  List<Map<String, dynamic>> _records = [];
  // 記錄被選到右邊的食物，格式：{'record': 食物資料, 'multiplier': 份數(預設1.0)}
  final List<Map<String, dynamic>> _selectedItems = [];
  int _targetCalories = 2000; // 預設目標熱量

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final List decoded = jsonDecode(prefs.getString('food_records') ?? '[]');
    setState(() {
      _records = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      _targetCalories = prefs.getInt('target_calories') ?? 2000;
    });
  }

  void _addToCalculator(Map<String, dynamic> record) {
    setState(() {
      _selectedItems.add({
        'record': record,
        'multiplier': 1.0, // 預設加進去是一份
      });
    });
  }

  void _updateMultiplier(int index, double delta) {
    setState(() {
      double current = _selectedItems[index]['multiplier'];
      current += delta;
      if (current <= 0) {
        _selectedItems.removeAt(index);
      } else {
        _selectedItems[index]['multiplier'] = current;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double totalKcal = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalCarbs = 0;

    for (var item in _selectedItems) {
      final record = item['record'];
      final double multiplier = item['multiplier'];
      final double weight = (record['total_weight_g'] ?? 0).toDouble();
      final nutrients = record['nutrients_per_100g'] ?? {};
      
      // 計算該份量的實際數值 (每100克數值 / 100 * 總克數 * 份數)
      totalKcal += ((nutrients['calories_kcal'] ?? 0) / 100) * weight * multiplier;
      totalProtein += ((nutrients['protein_g'] ?? 0) / 100) * weight * multiplier;
      totalFat += ((nutrients['fat_g'] ?? 0) / 100) * weight * multiplier;
      totalCarbs += ((nutrients['carbs_g'] ?? 0) / 100) * weight * multiplier;
    }

    double remainingKcal = _targetCalories - totalKcal;

    return Column(
      children: [
        // 上半部左右分欄
        Expanded(
          child: Row(
            children: [
              // 左側：歷史紀錄清單 (1/3 寬度)
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey.shade100,
                  child: ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (ctx, i) {
                      final record = _records[i];
                      final String? base64Img = record['image_base64'];
                      return InkWell(
                        onTap: () => _addToCalculator(record),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Column(
                              children: [
                                if (base64Img != null && base64Img.isNotEmpty)
                                  ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), height: 40, width: double.infinity, fit: BoxFit.cover))
                                else
                                  const Icon(Icons.restaurant, color: Colors.green),
                                const SizedBox(height: 4),
                                Text(record['food_name'] ?? '未命名', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              // 右側：選擇的食物計算清單 (2/3 寬度)
              Expanded(
                flex: 2,
                child: _selectedItems.isEmpty
                    ? const Center(child: Text('請從左側點選食物加入', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _selectedItems.length,
                        itemBuilder: (ctx, i) {
                          final item = _selectedItems[i];
                          final record = item['record'];
                          final double multiplier = item['multiplier'];
                          final double weight = (record['total_weight_g'] ?? 0).toDouble();
                          final nutrients = record['nutrients_per_100g'] ?? {};
                          
                          // 計算顯示數值
                          final kcal = ((nutrients['calories_kcal'] ?? 0) / 100) * weight * multiplier;
                          final protein = ((nutrients['protein_g'] ?? 0) / 100) * weight * multiplier;
                          final fat = ((nutrients['fat_g'] ?? 0) / 100) * weight * multiplier;
                          final carbs = ((nutrients['carbs_g'] ?? 0) / 100) * weight * multiplier;
                          final String? base64Img = record['image_base64'];

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  if (base64Img != null && base64Img.isNotEmpty)
                                    ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), height: 50, width: 50, fit: BoxFit.cover))
                                  else
                                    Container(width: 50, height: 50, color: Colors.green, child: const Icon(Icons.restaurant, color: Colors.white)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(record['food_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text('${(weight * multiplier).toStringAsFixed(0)}g | ${kcal.toStringAsFixed(0)} kcal', style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                                        Text('碳水:${carbs.toStringAsFixed(1)} 蛋白:${protein.toStringAsFixed(1)} 脂肪:${fat.toStringAsFixed(1)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _updateMultiplier(i, 0.5)), // 每次加 0.5 份
                                      Text('${multiplier} 份', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      IconButton(icon: const Icon(Icons.do_not_disturb_on, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _updateMultiplier(i, -0.5)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        // 下半部總計區塊
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('加總熱量: ${totalKcal.toStringAsFixed(0)} kcal', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('目標: $_targetCalories | 剩餘: ${remainingKcal.toStringAsFixed(0)}', style: TextStyle(color: remainingKcal < 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => setState(() => _selectedItems.clear()),
                    icon: const Icon(Icons.delete_sweep, color: Colors.white),
                    label: const Text('清空', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('碳水: ${totalCarbs.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.orange)),
                  Text('蛋白質: ${totalProtein.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.blue)),
                  Text('脂肪: ${totalFat.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.redAccent)),
                ],
              )
            ],
          ),
        )
      ],
    );
  }
}

// ==========================================
// 4. 設定頁面 (新增目標熱量設定)
// ==========================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyController = TextEditingController();
  final _targetCaloriesController = TextEditingController(); // 👇 新增
  String _selectedModel = 'gemini-3.8-flash';
  bool _uploadOriginal = false;

  final Map<String, String> _modelDescriptions = {
    'gemini-3.1-pro': '【優點】最強大的模型，精準度極高，適合複雜食物與詳細微量元素分析。\n【缺點】處理速度較慢，且免費 API 額度限制較嚴格。',
    'gemini-3.8-flash': '【優點】最新推薦模型，聰明且速度快，適合日常快速分析。\n【缺點】無明顯缺點，為首選方案。',
    'gemini-3.5-flash-lite': '【優點】輕量極速版，回覆速度最快，幾乎不卡頓。\n【缺點】只適合簡單清晰的食物圖片，複雜的組合餐點容易誤判。',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      _targetCaloriesController.text = (prefs.getInt('target_calories') ?? 2000).toString(); // 👇 載入目標熱量
      _selectedModel = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';
      _uploadOriginal = prefs.getBool('upload_original') ?? false;
    });
  }

  Future<void> _autoSaveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text.trim());
    await prefs.setInt('target_calories', int.tryParse(_targetCaloriesController.text.trim()) ?? 2000); // 👇 儲存目標熱量
    await prefs.setString('gemini_model', _selectedModel);
    await prefs.setBool('upload_original', _uploadOriginal);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 目標熱量設定
          const Text('每日目標熱量 (kcal)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _targetCaloriesController,
            keyboardType: TextInputType.number,
            onChanged: (val) => _autoSaveSettings(),
            decoration: const InputDecoration(hintText: '預設 2000', border: OutlineInputBorder(), prefixIcon: Icon(Icons.local_fire_department, color: Colors.orange)), 
          ),
          const SizedBox(height: 16),
          
          // API Key 設定
          const Text('Gemini API 金鑰', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            onChanged: (val) => _autoSaveSettings(), 
            decoration: const InputDecoration(hintText: '請輸入你的 API Key', border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key)), 
            obscureText: true
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () {}, child: const Text('如何免費申請 API Key？', style: TextStyle(decoration: TextDecoration.underline, fontSize: 13, color: Colors.blue))),
          ),
          const SizedBox(height: 12),
          
          // 模型選擇
          const Text('選擇 AI 分析模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gemini-3.1-pro', child: Text('Gemini 3.1 Pro (最強)')),
              DropdownMenuItem(value: 'gemini-3.8-flash', child: Text('Gemini 3.8 Flash (推薦)')),
              DropdownMenuItem(value: 'gemini-3.5-flash-lite', child: Text('Gemini 3.5 Flash-Lite (極速)')),
            ],
            onChanged: (val) { if (val != null) { setState(() => _selectedModel = val); _autoSaveSettings(); } },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
            child: Text(_modelDescriptions[_selectedModel] ?? '', style: const TextStyle(color: Colors.black87, height: 1.4)),
          ),
          const SizedBox(height: 24),

          // 上傳畫質設定
          const Text('進階設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: SwitchListTile(
              title: const Text('上傳原圖給 AI 分析', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('【開啟】AI 辨識更精準，但會消耗較多網路流量。\n【關閉】上傳前自動壓縮圖片，省流量速度快。', style: TextStyle(fontSize: 12, height: 1.3)),
              value: _uploadOriginal,
              activeColor: Colors.green,
              onChanged: (val) { setState(() => _uploadOriginal = val); _autoSaveSettings(); },
            ),
          ),
        ],
      ),
    );
  }
}
