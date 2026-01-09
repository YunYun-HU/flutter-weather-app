import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: WeatherPage(),
    );
  }
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final Dio dio = Dio();
  final TextEditingController cityController =
  TextEditingController(text: 'Taipei');

  String locationTitle = 'Taipei';

  bool loading = true;
  String? error;

  double? temperature;
  String? description;
  double? feelsLike;
  int? humidity;
  double? windSpeed;
  DateTime? sunrise;
  DateTime? sunset;
  String? iconUrl;

  @override
  void initState() {
    super.initState();
    fetchWeather();
  }

  @override
  void dispose() {
    cityController.dispose();
    super.dispose();
  }

  // 地名 -> 座標（中文查不到就用別名 fallback）
  Future<({double lat, double lon, String title})> geocodeFirst(String query) async {
    final apiKey = dotenv.env['OPENWEATHER_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENWEATHER_KEY not found');
    }

    const Map<String, String> zhToEnAlias = {
      '台北': 'Taipei',
      '臺北': 'Taipei',
      '新北': 'New Taipei',
      '桃園': 'Taoyuan',
      '台中': 'Taichung',
      '臺中': 'Taichung',
      '台南': 'Tainan',
      '臺南': 'Tainan',
      '高雄': 'Kaohsiung',
      '基隆': 'Keelung',
      '新竹市': 'Hsinchu',
      '嘉義市': 'Chiayi',
      '新竹縣': 'Hsinchu County',
      '苗栗': 'Miaoli',
      '彰化': 'Changhua',
      '南投': 'Nantou',
      '雲林': 'Yunlin',
      '嘉義縣': 'Chiayi County',
      '屏東': 'Pingtung',
      '宜蘭': 'Yilan',
      '花蓮': 'Hualien',
      '台東': 'Taitung',
      '臺東': 'Taitung',
      '澎湖': 'Penghu',
      '金門': 'Kinmen',
      '連江': 'Lienchiang',
      '竹市': 'Hsinchu',
      '竹縣': 'Hsinchu County',
      '嘉市': 'Chiayi',
      '嘉縣': 'Chiayi County',
      '馬祖': 'Lienchiang',
    };


    final q0 = query.trim();
    if (q0.isEmpty) {
      throw Exception('請輸入地點名稱');
    }

    Future<List<dynamic>> geoQuery(String q) async {
      final resp = await dio.get(
        'https://api.openweathermap.org/geo/1.0/direct',
        queryParameters: {
          'q': q,
          'limit': 5,
          'appid': apiKey,
        },
      );
      return resp.data as List;
    }

    //對照表
    final alias = zhToEnAlias[q0];
    List<dynamic> list;
    if (alias != null) {
      list = await geoQuery(alias);

      // alias 也查不到，再回退原輸入
      if (list.isEmpty) {
        list = await geoQuery(q0);
      }
    } else {
      //照原本查
      list = await geoQuery(q0);
    }

    if (list.isEmpty) {
      throw Exception('找不到地點：$q0');
    }

    //取第一筆
    final first = (list.first as Map).cast<String, dynamic>();
    final lat = (first['lat'] as num).toDouble();
    final lon = (first['lon'] as num).toDouble();

    // 優先 local_names 的繁中/中文
    final localNames = (first['local_names'] as Map?)?.cast<String, dynamic>();
    final nameZh = localNames?['zh_tw'] ?? localNames?['zh'] ?? localNames?['zh_cn'];
    final name = (nameZh ?? first['name'] ?? q0).toString();
    final title = name;

    return (lat: lat, lon: lon, title: title);
  }

  // 呼叫天氣 API
  Future<void> fetchWeather() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final q = cityController.text.trim();
      if (q.isEmpty) {
        throw Exception('請輸入地點名稱');
      }

      // 1) 地名 -> 座標
      final geo = await geocodeFirst(q);

      // 2) 座標 -> 天氣
      final apiKey = dotenv.env['OPENWEATHER_KEY']!;
      final response = await dio.get(
        'https://api.openweathermap.org/data/2.5/weather',
        queryParameters: {
          'lat': geo.lat,
          'lon': geo.lon,
          'appid': apiKey,
          'units': 'metric',
          'lang': 'zh_tw',
        },
      );

      final data = (response.data as Map).cast<String, dynamic>();
      final main = (data['main'] as Map).cast<String, dynamic>();
      final weather0 = (data['weather'] as List).first as Map<String, dynamic>;
      final wind = (data['wind'] as Map?)?.cast<String, dynamic>();
      final sys = (data['sys'] as Map?)?.cast<String, dynamic>();

      final iconCode = weather0['icon']?.toString();

      setState(() {
        locationTitle = geo.title;

        temperature = (main['temp'] as num).toDouble();
        feelsLike = (main['feels_like'] as num).toDouble();
        humidity = (main['humidity'] as num).toInt();
        description = weather0['description']?.toString();

        windSpeed = wind?['speed'] == null ? null : (wind!['speed'] as num).toDouble();

        final sr = sys?['sunrise'];
        final ss = sys?['sunset'];
        sunrise = sr == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((sr as num).toInt() * 1000, isUtc: true).toLocal();
        sunset = ss == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((ss as num).toInt() * 1000, isUtc: true).toLocal();

        iconUrl = iconCode == null ? null : 'https://openweathermap.org/img/wn/$iconCode@2x.png';

        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  String hhmm(DateTime? dt) {
    if (dt == null) return '-';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (loading) {
      body = const CircularProgressIndicator();
    } else if (error != null) {
      body = Text('錯誤：$error');
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            locationTitle,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          if (iconUrl != null) Image.network(iconUrl!, width: 80, height: 80),

          Text(
            '${temperature?.toStringAsFixed(1) ?? '-'} °C',
            style: const TextStyle(fontSize: 40, color: Colors.white70),
          ),
          const SizedBox(height: 8),

          Text(
            description ?? '',
            style: const TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 18),

          Text(
            '體感：${feelsLike?.toStringAsFixed(1) ?? '-'} °C',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70),
          ),
          const SizedBox(height: 18),

          Text(
            '濕度：${humidity ?? '-'} %',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70),
          ),
          const SizedBox(height: 18),

          Text(
            '風速：${windSpeed?.toStringAsFixed(1) ?? '-'} m/s',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70),
          ),
          const SizedBox(height: 18),

          Text(
            '日出：${hhmm(sunrise)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70),
          ),
          const SizedBox(height: 18),

          Text(
            '日落：${hhmm(sunset)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70),
          ),

          const SizedBox(height: 12),

          OutlinedButton(
            onPressed: fetchWeather,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.6),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('重新整理'),
          ),

        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Weather App'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                TextField(
                  controller: cityController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: '輸入城市/地點（可中文/英文）',
                    labelStyle: const TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white70),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: false,
                  ),
                  onSubmitted: (_) => fetchWeather(),
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(20),
                  child: body,
                ),
              ],
            ),
          ),
        ),
      ),
    );


  }
}
