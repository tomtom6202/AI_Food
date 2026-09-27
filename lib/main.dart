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
    // 讓主頁面可以呼叫這個方法來切換到設定頁(Index 2)
    final List<Widget> pages = [
      HomePage(onGoToSettings: () => setState(() => _currentIndex = 2)),
      const RecordsPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'AI 食物分析' : _currentIndex == 1 ? '營養紀錄清單' : '設定'),
        backgroundColor: Colors.green,
      ),
      body: pages[_currentIndex],
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

final Map<String, String> nutrientDisplayNames = {
  'calories_kcal': '熱量 (kcal)', 'protein_g': '蛋白質 (g)', 'fat_g': '脂肪 (g)', 'carbs_g': '碳水化合物 (g)',
  'dietary_fiber_g': '膳食纖維 (g)', 'cholesterol_mg': '膽固醇 (mg)', 'calcium_mg': '鈣 (mg)',
  'vitamin_A_ug': '維生素A (ug)', 'vitamin_B1_mg': '維生素B1 (mg)', 'vitamin_B2_mg': '維生素B2 (mg)',
  'vitamin_B6_mg': '維生素B6 (mg)', 'vitamin_B12_ug': '維生素B12 (ug)', 'vitamin_C_mg': '維生素C (mg)',
  'vitamin_D_ug': '維生素D (ug)', 'vitamin_E_mg': '維生素E (mg)', 'niacin_mg': '煙酸/尼克酸 (mg)',
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: scoreColor.withOpacity(0.2), border: Border.all(color: scoreColor), borderRadius: BorderRadius.circular(4)),
              child: Text(score, style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(reason, style: const TextStyle(color: Colors.black87)),
      ],
    ),
  );
}

// ==========================================
// 1. 主頁面
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
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, maxWidth: 500, maxHeight: 500, imageQuality: 60);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() { _imageBytes = bytes; });
    }
  }

  Future<void> _analyzeFood() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先拍照或從相簿選取食物照片')));
      return;
    }

    setState(() { _isLoading = true; });

    bool isRetrying = false;
    bool isCancelled = false;
    BuildContext? dialogContext;

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = (prefs.getString('gemini_api_key') ?? '').trim();
      final modelName = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';

      if (apiKey.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先切換至「設定」頁面輸入 API Key')));
        setState(() { _isLoading = false; });
        return;
      }

      final base64Image = base64Encode(_imageBytes!);
      final prompt = '''
你是一位專業的 AI 營養顧問。請分析照片中的食物，並參考備註：「${_noteController.text.trim()}」。
【必須遵守的規則】
1. 只輸出純 JSON 物件，嚴禁包含 Markdown 標籤。
2. 估算總重量(total_weight_g)，並給出每 100g 的營養數值(nutrients_per_100g)。(必填: calories_kcal, protein_g, fat_g, carbs_g)
3. 包含 "breakdown" 陣列：拆解各食材或獨立食物的 name, weight_g, calories_kcal。
4. 包含 "evaluation" 物件，評分(score: A/B/C/D)與說明(reason)：fitness(健身), weight_loss(瘦身), diversity(多樣性), overall(綜合)。
''';

      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey');
      final requestBody = jsonEncode({
        "contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": "image/jpeg", "data": base64Image}}]}],
        "generationConfig": {"response_mime_type": "application/json"}
      });

      // ================= 重試迴圈開始 =================
      while (!isCancelled) {
        final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: requestBody);

        if (response.statusCode == 200) {
          // 成功！如果重試視窗還開著，就把它關掉
          if (isRetrying && dialogContext != null && mounted) {
            Navigator.pop(dialogContext!);
            isRetrying = false;
          }

          final data = jsonDecode(response.body);
          String rawText = data['candidates'][0]['content']['parts'][0]['text'];
          int startIndex = rawText.indexOf('{');
          int endIndex = rawText.lastIndexOf('}');
          if (startIndex != -1 && endIndex != -1) rawText = rawText.substring(startIndex, endIndex + 1);

          if (!mounted) return;
          _showResultAndSaveDialog(jsonDecode(rawText), base64Image);
          break; // 跳出迴圈

        } else if (response.statusCode == 503) {
          // 遇到 503 伺服器忙碌
          if (!isRetrying) {
            isRetrying = true;
            if (!mounted) return;
            // 顯示排隊對話框
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) {
                dialogContext = ctx;
                return AlertDialog(
                  title: const Text('伺服器滿載中'),
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.green),
                      SizedBox(height: 16),
                      Text('排隊等待模型中，請稍後。\n如等待過久，請至設定中嘗試其他模型。', textAlign: TextAlign.center),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        isCancelled = true;
                        Navigator.pop(ctx);
                      },
                      child: const Text('取消', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      onPressed: () {
                        isCancelled = true;
                        Navigator.pop(ctx);
                        widget.onGoToSettings(); // 呼叫跳轉到設定頁
                      },
                      child: const Text('選擇其他模型', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                );
              },
            );
          }
          // 背景等待 0.5 秒後自動進行下一次迴圈重試
          await Future.delayed(const Duration(milliseconds: 500));
          continue;

        } else {
          // 其他非 503 的錯誤，正常報錯並中斷
          if (isRetrying && dialogContext != null && mounted) {
            Navigator.pop(dialogContext!);
            isRetrying = false;
          }
          
          String msg = '未知錯誤';
          try {
            msg = jsonDecode(response.body)['error']['message'] ?? response.body;
          } catch (_) { msg = response.body; }

          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('API 連線失敗 (${response.statusCode})'),
              content: SingleChildScrollView(child: Text('伺服器訊息:\n$msg')),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))],
            ),
          );
          break;
        }
      }
      // ================= 重試迴圈結束 =================

    } catch (e) {
      if (isRetrying && dialogContext != null && mounted) Navigator.pop(dialogContext!);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('發生錯誤'),
          content: SingleChildScrollView(child: Text(e.toString())),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))],
        ),
      );
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _showResultAndSaveDialog(Map<String, dynamic> data, String base64Img) {
    final nameCtrl = TextEditingController(text: data['food_name'] ?? '未命名食物');
    final num totalWeight = data['total_weight_g'] ?? 0;
    final Map<String, dynamic> nutrients = data['nutrients_per_100g'] ?? {};
    final num totalCalories = ((nutrients['calories_kcal'] ?? 0) / 100) * totalWeight;
    final List<dynamic>? breakdown = data['breakdown'];
    final Map<String, dynamic>? evaluation = data['evaluation'];

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
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '食物名稱', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [const Text('預估總重量', style: TextStyle(color: Colors.green)), Text('$totalWeight g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                      Column(children: [const Text('預估總熱量', style: TextStyle(color: Colors.green)), Text('${totalCalories.toStringAsFixed(1)} kcal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                    ],
                  ),
                ),
                const Divider(height: 24),
                if (breakdown != null && breakdown.isNotEmpty) ...[
                  const Text('🍔 食物組成拆解：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ...breakdown.map((item) => Padding(padding: const EdgeInsets.only(bottom: 4.0), child: Text('• ${item['name']} (${item['weight_g']}g, ${item['calories_kcal']}大卡)'))),
                  const Divider(height: 24),
                ],
                if (evaluation != null) ...[
                  const Text('🤖 AI 專業評價：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  _buildEvalRow('健身', evaluation['fitness']), _buildEvalRow('瘦身', evaluation['weight_loss']),
                  _buildEvalRow('多樣性', evaluation['diversity']), _buildEvalRow('綜合', evaluation['overall']),
                  const Divider(height: 24),
                ],
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
              data['image_base64'] = base64Img;
              final prefs = await SharedPreferences.getInstance();
              final List list = jsonDecode(prefs.getString('food_records') ?? '[]');
              list.insert(0, data);
              await prefs.setString('food_records', jsonEncode(list));
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已儲存！')));
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
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
              child: _imageBytes == null
                  ? const Center(child: Text('請點選下方按鈕拍照', style: TextStyle(color: Colors.grey)))
                  : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('拍照'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
              ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('相簿'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: '文字備註 (例如：無糖、半份、去皮)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.edit_note))),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : _analyzeFood,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('送出 AI 分析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. 紀錄頁面
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

  void _exportJson() {
    final jsonStr = jsonEncode(_records);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('匯出紀錄'),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(jsonStr))),
        actions: [
          TextButton(
            onPressed: () { Clipboard.setData(ClipboardData(text: jsonStr)); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已複製！'))); },
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
        content: TextField(controller: inputCtrl, maxLines: 8, decoration: const InputDecoration(hintText: '請貼上 JSON...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                final List parsed = jsonDecode(inputCtrl.text.trim());
                setState(() { _records = parsed.map((e) => Map<String, dynamic>.from(e)).toList(); });
                await _saveRecords();
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('匯入成功！')));
              } catch (_) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 格式有誤'))); }
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
    final List<dynamic>? breakdown = item['breakdown'];
    final Map<String, dynamic>? evaluation = item['evaluation'];
    final String? base64Img = item['image_base64'];
    num totalCalories = item['calculated_total_calories'] ?? (((nutrients['calories_kcal'] ?? 0) / 100) * (item['total_weight_g'] ?? 0));

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
                          setState(() { item['food_name'] = editCtrl.text.trim(); });
                          _saveRecords(); Navigator.pop(editCtx); Navigator.pop(ctx);
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
                if (base64Img != null && base64Img.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 12.0), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(base64Img), height: 180, width: double.infinity, fit: BoxFit.cover))),
                Text('紀錄時間: ${item['record_date'] ?? '無'}'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [Text('總重: ${item['total_weight_g'] ?? 0}g', style: const TextStyle(fontWeight: FontWeight.bold)), Text('總熱量: ${totalCalories.toStringAsFixed(1)} kcal', style: const TextStyle(fontWeight: FontWeight.bold))],
                  ),
                ),
                const Divider(height: 20),
                if (breakdown != null && breakdown.isNotEmpty) ...[
                  const Text('🍔 拆解：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ...breakdown.map((b) => Text('• ${b['name']} (${b['weight_g']}g, ${b['calories_kcal']}大卡)')),
                  const Divider(height: 20),
                ],
                if (evaluation != null) ...[
                  const Text('🤖 評價：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  _buildEvalRow('健身', evaluation['fitness']), _buildEvalRow('瘦身', evaluation['weight_loss']),
                  _buildEvalRow('多樣性', evaluation['diversity']), _buildEvalRow('綜合', evaluation['overall']),
                  const Divider(height: 20),
                ],
                const Text('📊 每 100g 數值：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ...nutrients.entries.where((e) => e.value != null).map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 2.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(nutrientDisplayNames[e.key] ?? e.key), Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold))]))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () { setState(() { _records.removeAt(index); }); _saveRecords(); Navigator.pop(ctx); }, child: const Text('刪除此筆')),
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
              OutlinedButton.icon(onPressed: _exportJson, icon: const Icon(Icons.file_download), label: const Text('匯出')),
              OutlinedButton.icon(onPressed: _importJson, icon: const Icon(Icons.file_upload), label: const Text('上傳')),
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
                      leading: base64Img != null && base64Img.isNotEmpty
                          ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), width: 50, height: 50, fit: BoxFit.cover))
                          : const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.restaurant, color: Colors.white)),
                      title: Text(item['food_name'] ?? '未命名食物', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item['record_date'] ?? ''}\n${item['total_weight_g'] ?? 0}g · ${totalCalories.toStringAsFixed(0)} kcal'),
                      isThreeLine: true,
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
// 3. 設定頁面
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
    await prefs.setString('gemini_api_key', _apiKeyController.text.trim());
    await prefs.setString('gemini_model', _selectedModel);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設定已成功儲存！')));
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
          TextField(controller: _apiKeyController, decoration: const InputDecoration(hintText: '請輸入你的 API Key', border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key)), obscureText: true),
          const SizedBox(height: 20),
          const Text('選擇模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gemini-3.8-flash', child: Text('Gemini 3.8 Flash (最新)')),
              DropdownMenuItem(value: 'gemini-3.7-flash', child: Text('Gemini 3.7 Flash')),
              DropdownMenuItem(value: 'gemini-3.5-flash-lite', child: Text('Gemini 3.5 Flash-Lite')),
            ],
            onChanged: (val) { if (val != null) setState(() => _selectedModel = val); },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white), onPressed: _saveSettings, child: const Text('儲存設定', style: TextStyle(fontSize: 18))),
          ),
        ],
      ),
    );
  }
}
