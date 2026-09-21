import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const defaultConfigUrl =
    'https://ghproxy.net/https://raw.githubusercontent.com/JackEric6/movie/refs/heads/main/movie2';
const spiderChannel = MethodChannel('congcong/spider');

class TVBoxSite {
  const TVBoxSite({
    required this.key,
    required this.name,
    required this.api,
    required this.type,
    required this.searchable,
    required this.filterable,
    required this.ext,
    required this.jar,
    required this.playUrl,
    required this.icon,
    required this.categories,
  });

  final String key;
  final String name;
  final String api;
  final int type;
  final bool searchable;
  final bool filterable;
  final String ext;
  final String jar;
  final String playUrl;
  final String icon;
  final List<String> categories;

  bool get isIOSExecutable =>
      type != 3 || api.startsWith('http://') || api.startsWith('https://');

  factory TVBoxSite.fromJson(Map<String, dynamic> json, String defaultJar) {
    final ext = json['ext'];
    return TVBoxSite(
      key: '${json['key'] ?? json['id'] ?? ''}',
      name: '${json['name'] ?? json['key'] ?? '未命名站点'}',
      api: '${json['api'] ?? ''}',
      type: _toInt(json['type']) ?? 1,
      searchable: (_toInt(json['searchable']) ?? 1) != 0,
      filterable: (_toInt(json['filterable']) ?? 1) != 0,
      ext: ext is String ? ext : jsonEncode(ext ?? ''),
      jar: '${json['jar'] ?? defaultJar}',
      playUrl: '${json['playUrl'] ?? json['play_url'] ?? ''}',
      icon: '${json['icon'] ?? ''}',
      categories:
          (json['categories'] as List?)?.map((value) => '$value').toList() ??
          const [],
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }
}

class TVBoxCategory {
  const TVBoxCategory(this.id, this.name);
  final String id;
  final String name;
}

class VideoItem {
  const VideoItem({
    required this.id,
    required this.name,
    required this.poster,
    required this.remark,
    required this.sourceKey,
  });
  final String id;
  final String name;
  final String poster;
  final String remark;
  final String sourceKey;
}

class Episode {
  const Episode({
    required this.id,
    required this.name,
    required this.url,
    required this.flag,
  });
  final String id;
  final String name;
  final String url;
  final String flag;
}

class VideoDetail {
  const VideoDetail({
    required this.id,
    required this.name,
    required this.poster,
    required this.remark,
    required this.description,
    required this.episodes,
    required this.sourceKey,
  });
  final String id;
  final String name;
  final String poster;
  final String remark;
  final String description;
  final List<Episode> episodes;
  final String sourceKey;
}

class PlayResult {
  const PlayResult(this.url, this.headers);
  final Uri url;
  final Map<String, String> headers;
}

class ConfigLoadResult {
  const ConfigLoadResult(this.sites, this.address, this.fromCache);
  final List<TVBoxSite> sites;
  final String address;
  final bool fromCache;
}

class ConfigStore {
  static const addressKey = 'congcong.config.address';
  static const cacheKey = 'congcong.config.cache';

  Future<String> get savedAddress async =>
      (await SharedPreferences.getInstance()).getString(addressKey) ??
      defaultConfigUrl;

  Future<ConfigLoadResult> load([String? address]) async {
    final prefs = await SharedPreferences.getInstance();
    final requested =
        (address ?? prefs.getString(addressKey) ?? defaultConfigUrl).trim();
    if (requested.isEmpty) throw Exception('配置地址无效');
    await prefs.setString(addressKey, requested);
    try {
      final data = await _loadData(requested, 0);
      final sites = _parseSites(data);
      if (sites.isEmpty) throw Exception('配置中没有可用影视站点');
      await prefs.setString(cacheKey, utf8.decode(data));
      return ConfigLoadResult(sites, requested, false);
    } catch (error) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final sites = _parseSites(utf8.encode(cached));
        if (sites.isNotEmpty) return ConfigLoadResult(sites, requested, true);
      }
      rethrow;
    }
  }

  Future<http.Response> _get(String address) async {
    final headers = {'User-Agent': '丛丛影视/1.0 (Flutter iOS)'};
    final response = await http
        .get(Uri.parse(address), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 400)
      return response;
    if (address.startsWith('https://ghproxy.net/https://')) {
      final fallback = address.substring('https://ghproxy.net/'.length);
      return http
          .get(Uri.parse(fallback), headers: headers)
          .timeout(const Duration(seconds: 20));
    }
    throw Exception('配置地址返回 HTTP ${response.statusCode}');
  }

  Future<List<int>> _loadData(String address, int depth) async {
    if (depth >= 3) throw Exception('配置仓库嵌套层级过深');
    final clean = address.split(';pk;').first;
    final response = await _get(clean);
    final object = jsonDecode(utf8.decode(response.bodyBytes));
    if (object is Map<String, dynamic> &&
        object['sites'] == null &&
        object['urls'] is List) {
      for (final item in object['urls']) {
        if (item is Map) {
          final next = '${item['url'] ?? item['api'] ?? ''}'.trim();
          if (next.isNotEmpty) {
            try {
              return await _loadData(next, depth + 1);
            } catch (_) {}
          }
        }
      }
      throw Exception('多仓配置中没有可用地址');
    }
    return response.bodyBytes;
  }

  List<TVBoxSite> _parseSites(List<int> data) {
    final root = jsonDecode(utf8.decode(data));
    if (root is! Map) return const [];
    final container = root['data'] is Map ? root['data'] as Map : root;
    final rawSites = container['sites'] is List
        ? container['sites'] as List
        : const [];
    final defaultJar = '${root['spider'] ?? container['spider'] ?? ''}';
    return rawSites
        .whereType<Map>()
        .map((item) {
          return TVBoxSite.fromJson(
            Map<String, dynamic>.from(item),
            defaultJar,
          );
        })
        .where((site) => site.key.isNotEmpty && site.api.isNotEmpty)
        .toList();
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
  }
}

class TVBoxService {
  String bridgeBaseUrl = '';
  String bridgeToken = '';

  String? _bridgeApi(TVBoxSite site) {
    if (bridgeBaseUrl.trim().isEmpty || site.isIOSExecutable) return null;
    final base = bridgeBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return '$base/api/${Uri.encodeComponent(site.key)}';
  }

  Future<String> _remoteSpider(
    TVBoxSite site,
    String action,
    Map<String, dynamic> arguments,
  ) async {
    Object? gatewayError;
    if (bridgeBaseUrl.trim().isNotEmpty) {
      try {
        final object = await _gatewayInvoke(site, action, arguments);
        return jsonEncode(object);
      } catch (error) {
        gatewayError = error;
      }
    }

    final cms = _bridgeApi(site);
    if (cms != null) {
      if (action == 'player') {
        final data = await _request('$cms/play', {
          'flag': '${arguments['flag'] ?? ''}',
          'id': '${arguments['id'] ?? ''}',
        });
        return utf8.decode(data);
      }
      final query = switch (action) {
        'home' => {'ac': 'class'},
        'category' => {
          't': '${arguments['tid'] ?? ''}',
          'pg': '${arguments['page'] ?? '1'}',
        },
        'search' => {'wd': '${arguments['keyword'] ?? ''}'},
        'detail' => {
          'ac': 'detail',
          'ids': ((arguments['ids'] as List?)?.first ?? '') as String,
        },
        _ => <String, String>{},
      };
      final data = await _request(cms, query);
      return utf8.decode(data);
    }

    throw Exception(
      gatewayError == null
          ? '此 Android spider 需要配置 JAR Bridge 地址'
          : 'JAR Bridge 不可用：$gatewayError',
    );
  }

  Future<Map<String, dynamic>> _gatewayInvoke(
    TVBoxSite site,
    String action,
    Map<String, dynamic> arguments,
  ) async {
    final endpoint =
        '${bridgeBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/v1/spider/invoke';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': '丛丛影视/1.0 (Flutter iOS)',
    };
    if (bridgeToken.trim().isNotEmpty)
      headers['Authorization'] = 'Bearer ${bridgeToken.trim()}';
    final body = {
      'version': 1,
      'action': action,
      'site': {
        'key': site.key,
        'api': site.api,
        'jar': site.jar,
        'ext': site.ext,
        'quickSearch': site.searchable,
      },
      'arguments': arguments,
    };
    final response = await http
        .post(Uri.parse(endpoint), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw Exception('Gateway HTTP ${response.statusCode}');
    final object = jsonDecode(utf8.decode(response.bodyBytes));
    if (object is! Map) throw Exception('Gateway 返回格式无效');
    if (object['code'] != null && object['message'] != null)
      throw Exception('${object['code']}: ${object['message']}');
    return Map<String, dynamic>.from(object);
  }

  Future<HomePage> home(TVBoxSite site) async {
    if (site.type == 3) {
      final bridge = _bridgeApi(site);
      if (bridge != null) {
        final text = await _remoteSpider(site, 'home', {'filter': true});
        return _parseHome(text, site, bridgeBaseUrl);
      }
      final text = await _script(site, 'home', const []);
      final page = _parseHome(text, site);
      if (page.videos.isNotEmpty) return page;
      try {
        final fallback = await _script(site, 'homeVod', const []);
        return HomePage(page.categories, _parseList(fallback, site));
      } catch (_) {
        return page;
      }
    }
    final data = await _request(site.api, const {});
    return _parseHome(utf8.decode(data), site);
  }

  Future<List<VideoItem>> category(
    TVBoxSite site,
    TVBoxCategory category,
  ) async {
    if (site.type == 3) {
      final bridge = _bridgeApi(site);
      if (bridge != null) {
        final text = await _remoteSpider(site, 'category', {
          'tid': category.id,
          'page': '1',
          'filter': site.filterable,
          'extend': {},
        });
        return _parseList(text, site, bridgeBaseUrl);
      }
      return _parseList(
        await _script(site, 'category', [category.id, '1', false, {}]),
        site,
      );
    }
    final data = await _request(site.api, {
      'ac': 'list',
      't': category.id,
      'pg': '1',
      'class': category.id,
    });
    return _parseList(utf8.decode(data), site);
  }

  Future<List<VideoItem>> search(TVBoxSite site, String query) async {
    if (site.type == 3) {
      final bridge = _bridgeApi(site);
      if (bridge != null) {
        final text = await _remoteSpider(site, 'search', {
          'keyword': query,
          'quick': false,
          'page': '1',
        });
        return _parseList(text, site, bridgeBaseUrl);
      }
      return _parseList(await _script(site, 'search', [query, false]), site);
    }
    final data = await _request(site.api, {
      'wd': query,
      'pg': '1',
      'ac': 'list',
    });
    return _parseList(utf8.decode(data), site);
  }

  Future<VideoDetail> detail(TVBoxSite site, VideoItem item) async {
    final bridge = _bridgeApi(site);
    final text = site.type == 3
        ? bridge != null
              ? await _remoteSpider(site, 'detail', {
                  'ids': [item.id],
                  'verifyResource': false,
                })
              : await _script(site, 'detail', [item.id])
        : utf8.decode(
            await _request(site.api, {'ac': 'detail', 'ids': item.id}),
          );
    final detail = _parseDetail(text, site, bridge);
    if (detail == null) throw Exception('站点没有返回详情数据');
    return detail;
  }

  Future<PlayResult> play(TVBoxSite site, Episode episode) async {
    final direct = Uri.tryParse(episode.url);
    if (direct != null && direct.hasScheme) return PlayResult(direct, const {});
    final bridge = _bridgeApi(site);
    if (site.type == 3 && bridge != null) {
      final text = await _remoteSpider(site, 'player', {
        'flag': episode.flag,
        'id': episode.url,
        'vipFlags': [],
      });
      final result = _parsePlay(text);
      if (result != null) return result;
    }
    if (site.type == 3) {
      final result = _parsePlay(
        await _script(site, 'play', [episode.flag, episode.url, const []]),
      );
      if (result != null) return result;
    }
    if (site.playUrl.isNotEmpty) {
      final url = Uri.tryParse('${site.playUrl}${episode.url}');
      if (url != null) return PlayResult(url, const {});
    }
    throw Exception('此选集没有可播放地址');
  }

  Future<String> _script(
    TVBoxSite site,
    String method,
    List<dynamic> arguments,
  ) async {
    if (!site.isIOSExecutable) {
      throw Exception('${site.name} 使用 Android spider2.jar（DEX），iOS 无法直接执行');
    }
    final result = await spiderChannel.invokeMethod<String>('executeSpider', {
      'api': site.api,
      'ext': site.ext,
      'method': method,
      'arguments': arguments,
    });
    if (result == null || result.isEmpty) throw Exception('动态脚本没有返回结果');
    return result;
  }

  Future<List<int>> _request(String address, Map<String, String> params) async {
    final uri = Uri.parse(address).replace(
      queryParameters: {...Uri.parse(address).queryParameters, ...params},
    );
    final headers = <String, String>{'User-Agent': '丛丛影视/1.0 (Flutter iOS)'};
    if (bridgeToken.trim().isNotEmpty)
      headers['Authorization'] = 'Bearer ${bridgeToken.trim()}';
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 400)
      throw Exception('站点返回 HTTP ${response.statusCode}');
    return response.bodyBytes;
  }

  HomePage _parseHome(String text, TVBoxSite site, [String? baseAddress]) {
    final object = _decode(text);
    if (object == null) return HomePage(const [], const []);
    final root = _unwrap(object);
    final categories = _categoryValues(root)
        .asMap()
        .entries
        .map((entry) {
          final value = entry.value;
          if (value is! Map) return null;
          final id =
              '${value['type_id'] ?? value['id'] ?? value['typeId'] ?? entry.key + 1}';
          final name =
              '${value['type_name'] ?? value['name'] ?? value['title'] ?? id}';
          return TVBoxCategory(id, name);
        })
        .whereType<TVBoxCategory>()
        .toList();
    return HomePage(categories, _parseListObject(root, site, baseAddress));
  }

  List<VideoItem> _parseList(
    String text,
    TVBoxSite site, [
    String? baseAddress,
  ]) {
    final object = _decode(text);
    return object == null
        ? const []
        : _parseListObject(_unwrap(object), site, baseAddress);
  }

  List<VideoItem> _parseListObject(
    dynamic root,
    TVBoxSite site, [
    String? baseAddress,
  ]) {
    final values = root is List
        ? root
        : root is Map
        ? (root['list'] ??
              root['vod'] ??
              root['data'] ??
              root['result'] ??
              const [])
        : const [];
    if (values is! List) return const [];
    return values.asMap().entries.where((entry) => entry.value is Map).map((
      entry,
    ) {
      final item = Map<String, dynamic>.from(entry.value as Map);
      final id =
          '${item['vod_id'] ?? item['id'] ?? item['url'] ?? 'item-${entry.key}'}';
      final name =
          '${item['vod_name'] ?? item['name'] ?? item['title'] ?? '未命名'}';
      return VideoItem(
        id: id,
        name: name,
        poster: _absolute(
          '${item['vod_pic'] ?? item['pic'] ?? item['poster'] ?? ''}',
          baseAddress ?? site.api,
        ),
        remark:
            '${item['vod_remarks'] ?? item['remarks'] ?? item['remark'] ?? ''}',
        sourceKey: site.key,
      );
    }).toList();
  }

  VideoDetail? _parseDetail(
    String text,
    TVBoxSite site, [
    String? baseAddress,
  ]) {
    final object = _decode(text);
    if (object == null) return null;
    final root = _unwrap(object);
    Map<String, dynamic>? item;
    if (root is Map) {
      if (root['list'] is List && (root['list'] as List).isNotEmpty)
        item = Map<String, dynamic>.from(root['list'][0]);
      if (item == null &&
          root['vod'] is List &&
          (root['vod'] as List).isNotEmpty)
        item = Map<String, dynamic>.from(root['vod'][0]);
      if (item == null &&
          (root.containsKey('vod_id') ||
              root.containsKey('id') ||
              root.containsKey('vod_name')))
        item = Map<String, dynamic>.from(root);
    } else if (root is List && root.isNotEmpty && root.first is Map) {
      item = Map<String, dynamic>.from(root.first);
    }
    if (item == null) return null;
    final sources =
        '${item['vod_play_from'] ?? item['play_from'] ?? item['from'] ?? ''}'
            .split(r'$$$');
    final groups =
        '${item['vod_play_url'] ?? item['play_url'] ?? item['url'] ?? ''}'
            .split(r'$$$');
    final episodes = <Episode>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final flag = groupIndex < sources.length && sources[groupIndex].isNotEmpty
          ? sources[groupIndex]
          : '线路${groupIndex + 1}';
      for (final pair in groups[groupIndex].split('#')) {
        final parts = pair.split(r'$');
        if (parts.isEmpty || parts.last.isEmpty) continue;
        final title = parts.first.trim().isEmpty ? '播放' : parts.first.trim();
        final url = parts.length > 1 ? parts[1] : parts.first;
        episodes.add(
          Episode(
            id: '$groupIndex-$title-$url',
            name: '$flag · $title',
            url: _absolute(url, site.api),
            flag: flag,
          ),
        );
      }
    }
    return VideoDetail(
      id: '${item['vod_id'] ?? item['id'] ?? item['url'] ?? ''}',
      name: '${item['vod_name'] ?? item['name'] ?? item['title'] ?? '未命名'}',
      poster: _absolute(
        '${item['vod_pic'] ?? item['pic'] ?? item['poster'] ?? ''}',
        baseAddress ?? site.api,
      ),
      remark:
          '${item['vod_remarks'] ?? item['remarks'] ?? item['remark'] ?? ''}',
      description:
          '${item['vod_content'] ?? item['vod_blurb'] ?? item['content'] ?? item['desc'] ?? ''}',
      episodes: episodes,
      sourceKey: site.key,
    );
  }

  PlayResult? _parsePlay(String text) {
    final object = _decode(text);
    if (object is Map) {
      final root = object['data'] is Map ? object['data'] : object;
      final value =
          '${root['url'] ?? root['playUrl'] ?? root['play_url'] ?? ''}';
      final url = Uri.tryParse(value);
      if (url != null && url.hasScheme) {
        final raw = root['header'] ?? root['headers'];
        final headers = raw is Map
            ? raw.map((key, value) => MapEntry('$key', '$value'))
            : <String, String>{};
        return PlayResult(url, headers);
      }
    }
    final url = Uri.tryParse(text.trim());
    return url != null && url.hasScheme ? PlayResult(url, const {}) : null;
  }

  dynamic _decode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  dynamic _unwrap(dynamic object) {
    if (object is Map && object['data'] is Map ||
        object is Map && object['data'] is List)
      return object['data'];
    if (object is Map && object['result'] is Map ||
        object is Map && object['result'] is List)
      return object['result'];
    return object;
  }

  List<dynamic> _categoryValues(dynamic object) {
    if (object is! Map) return const [];
    return (object['class'] as List?) ??
        (object['categories'] as List?) ??
        (object['type'] as List?) ??
        const [];
  }

  String _absolute(String value, String base) {
    if (value.isEmpty || Uri.tryParse(value)?.hasScheme == true) return value;
    final baseUri = Uri.tryParse(base);
    return baseUri == null ? value : baseUri.resolve(value).toString();
  }
}

class HomePage {
  const HomePage(this.categories, this.videos);
  final List<TVBoxCategory> categories;
  final List<VideoItem> videos;
}

class AppModel extends ChangeNotifier {
  final configStore = ConfigStore();
  final service = TVBoxService();
  List<TVBoxSite> sites = const [];
  TVBoxSite? selectedSite;
  List<TVBoxCategory> categories = const [];
  List<VideoItem> videos = const [];
  String configUrl = defaultConfigUrl;
  String bridgeUrl = '';
  String bridgeToken = '';
  String message = '正在加载配置…';
  String error = '';
  bool loading = false;

  Future<void> loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    bridgeUrl = prefs.getString('congcong.bridge.url') ?? '';
    bridgeToken = prefs.getString('congcong.bridge.token') ?? '';
    service.bridgeBaseUrl = bridgeUrl;
    service.bridgeToken = bridgeToken;
  }

  Future<void> saveBridgeSettings(String value, String token) async {
    bridgeUrl = value.trim().replaceFirst(RegExp(r'/+$'), '');
    bridgeToken = token.trim();
    service.bridgeBaseUrl = bridgeUrl;
    service.bridgeToken = bridgeToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('congcong.bridge.url', bridgeUrl);
    await prefs.setString('congcong.bridge.token', bridgeToken);
    notifyListeners();
  }

  Future<void> loadConfig([String? address]) async {
    loading = true;
    error = '';
    message = '正在读取配置…';
    notifyListeners();
    try {
      final result = await configStore.load(address);
      configUrl = result.address;
      sites = result.sites;
      final previousKey = selectedSite?.key;
      selectedSite = sites.isEmpty
          ? null
          : sites.firstWhere(
              (site) => site.key == previousKey,
              orElse: () => sites.first,
            );
      message = result.fromCache ? '网络不可用，已使用上次缓存配置' : '配置已更新';
      await loadHome();
      return;
    } catch (e) {
      error = '$e';
      message = '配置加载失败';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadHome() async {
    final site = selectedSite;
    if (site == null) {
      loading = false;
      message = '配置中没有可用影视站点';
      notifyListeners();
      return;
    }
    loading = true;
    error = '';
    notifyListeners();
    try {
      final page = await service.home(site);
      categories = page.categories;
      videos = page.videos;
      message = '${site.name} · ${videos.length} 个内容';
    } catch (e) {
      error = '$e';
      message = '首页加载失败';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadCategory(TVBoxCategory category) async {
    final site = selectedSite;
    if (site == null) return;
    loading = true;
    error = '';
    notifyListeners();
    try {
      videos = await service.category(site, category);
      message = '${category.name} · ${videos.length} 个内容';
    } catch (e) {
      error = '$e';
      message = '分类加载失败';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> search(String query) async {
    final site = selectedSite;
    if (site == null || query.trim().isEmpty) return loadHome();
    loading = true;
    error = '';
    notifyListeners();
    try {
      videos = await service.search(site, query.trim());
      message = '搜索“${query.trim()}” · ${videos.length} 个结果';
    } catch (e) {
      error = '$e';
      message = '搜索失败';
    }
    loading = false;
    notifyListeners();
  }
}

void main() => runApp(const CongcongApp());

class CongcongApp extends StatefulWidget {
  const CongcongApp({super.key});
  @override
  State<CongcongApp> createState() => _CongcongAppState();
}

class _CongcongAppState extends State<CongcongApp> {
  final model = AppModel();
  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    await model.loadSavedSettings();
    await model.loadConfig();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '丛丛影视',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(model: model),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.model, super.key});
  final AppModel model;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final searchController = TextEditingController();
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.model,
      builder: (context, _) {
        final model = widget.model;
        return Scaffold(
          appBar: AppBar(
            title: const Text('丛丛影视'),
            actions: [
              IconButton(
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => model.loadConfig(),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(context, model)),
                if (model.loading && model.videos.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (model.videos.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyState(context, model),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _VideoCard(
                          item: model.videos[index],
                          onTap: () =>
                              _openDetail(context, model.videos[index]),
                        ),
                        childCount: model.videos.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190,
                            mainAxisExtent: 290,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 18,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, AppModel model) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (model.sites.length > 1)
            DropdownButton<TVBoxSite>(
              isExpanded: true,
              value: model.selectedSite,
              items: model.sites
                  .map(
                    (site) => DropdownMenuItem(
                      value: site,
                      child: Text(site.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (site) {
                if (site != null) {
                  model.selectedSite = site;
                  model.loadHome();
                }
              },
            )
          else if (model.selectedSite != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                model.selectedSite!.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: model.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索影视',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (model.categories.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: model.categories.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  if (index == 0)
                    return ActionChip(
                      label: const Text('推荐'),
                      onPressed: model.loadHome,
                    );
                  final category = model.categories[index - 1];
                  return ActionChip(
                    label: Text(category.name),
                    onPressed: () => model.loadCategory(category),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (model.loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (model.loading) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model.error.isEmpty
                      ? model.message
                      : '${model.message}：${model.error}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: model.error.isEmpty ? null : Colors.orangeAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, AppModel model) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined, size: 56),
            const SizedBox(height: 12),
            Text(model.message, style: Theme.of(context).textTheme.titleMedium),
            if (model.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(model.error, textAlign: TextAlign.center),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: model.error.isEmpty
                  ? () => _openSettings(context)
                  : model.loadHome,
              icon: Icon(model.error.isEmpty ? Icons.settings : Icons.refresh),
              label: Text(model.error.isEmpty ? '打开设置' : '重试'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettingsSheet(model: widget.model),
    );
  }

  void _openDetail(BuildContext context, VideoItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(model: widget.model, item: item),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.item, required this.onTap});
  final VideoItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.poster.isEmpty
                      ? const ColoredBox(
                          color: Colors.white10,
                          child: Icon(Icons.movie_outlined),
                        )
                      : Image.network(
                          item.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Colors.white10,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
                if (item.remark.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Colors.black54,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(
                          item.remark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class DetailScreen extends StatefulWidget {
  const DetailScreen({required this.model, required this.item, super.key});
  final AppModel model;
  final VideoItem item;
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Future<VideoDetail> future;
  @override
  void initState() {
    super.initState();
    future = widget.model.service.detail(
      widget.model.selectedSite!,
      widget.item,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: FutureBuilder<VideoDetail>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('${snapshot.error}'),
              ),
            );
          final detail = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    height: 158,
                    child: detail.poster.isEmpty
                        ? const ColoredBox(color: Colors.white10)
                        : Image.network(
                            detail.poster,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Colors.white10),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (detail.remark.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(detail.remark),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${detail.episodes.length} 集',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (detail.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(detail.description),
                ),
              const SizedBox(height: 18),
              Text('选集', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: detail.episodes
                    .map(
                      (episode) => OutlinedButton(
                        onPressed: () => _play(episode),
                        child: Text(
                          episode.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _play(Episode episode) async {
    try {
      final result = await widget.model.service.play(
        widget.model.selectedSite!,
        episode,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(result: result, title: widget.item.name),
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.result, required this.title, super.key});
  final PlayResult result;
  final String title;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController controller;
  @override
  void initState() {
    super.initState();
    controller =
        VideoPlayerController.networkUrl(
            widget.result.url,
            httpHeaders: widget.result.headers,
          )
          ..initialize().then((_) {
            if (mounted) {
              setState(() {});
              controller.play();
            }
          });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Center(
      child: controller.value.isInitialized
          ? AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  VideoPlayer(controller),
                  VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.all(12),
                  ),
                ],
              ),
            )
          : const CircularProgressIndicator(),
    ),
  );
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({required this.model, super.key});
  final AppModel model;
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController controller = TextEditingController(
    text: widget.model.configUrl,
  );
  late final TextEditingController bridgeController = TextEditingController(
    text: widget.model.bridgeUrl,
  );
  late final TextEditingController tokenController = TextEditingController(
    text: widget.model.bridgeToken,
  );
  bool loading = false;
  @override
  void dispose() {
    controller.dispose();
    bridgeController.dispose();
    tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 20,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('配置设置', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 3,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'TVBox 配置地址',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bridgeController,
            maxLines: 2,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'JAR Bridge / Spider Gateway 地址（可选）',
              hintText: '例如 https://gateway.example.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tokenController,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Gateway Token（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '推荐使用 tvbox-Swift-macOS 的 Spider Gateway：它通过 Android Worker 执行 csp_* DEX；兼容 CMS 的 /api/{key} Bridge 也可以使用。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : _reload,
              icon: const Icon(Icons.refresh),
              label: Text(loading ? '正在加载' : '保存并加载'),
            ),
          ),
          const SizedBox(height: 8),
          Text('当前站点：${widget.model.selectedSite?.name ?? '未选择'}'),
          Text('站点数量：${widget.model.sites.length}'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await widget.model.configStore.clearCache();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('清除配置缓存'),
          ),
        ],
      ),
    ),
  );
  Future<void> _reload() async {
    setState(() => loading = true);
    await widget.model.saveBridgeSettings(
      bridgeController.text,
      tokenController.text,
    );
    await widget.model.loadConfig(controller.text);
    if (mounted) {
      setState(() => loading = false);
      if (widget.model.error.isEmpty) Navigator.pop(context);
    }
  }
}
