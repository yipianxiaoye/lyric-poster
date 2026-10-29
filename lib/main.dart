import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'netease_client.dart';
import 'poster_document.dart';
import 'color_picker.dart';
import 'font_library.dart';
import 'poster_renderer.dart';
import 'history_store.dart';
import 'editor_fields.dart';
import 'about_page.dart';
import 'app_motion.dart';
import 'app_updates.dart';
import 'update_widgets.dart';

export 'netease_client.dart';

void main() => runApp(const LyricPosterApp());

class ThemePreset {
  const ThemePreset(this.id, this.name, this.seed, this.scaffold);
  final String id, name;
  final Color seed, scaffold;
}

const themePresets = <ThemePreset>[
  ThemePreset('violet', '薰衣草', Color(0xFF9B8AFB), Color(0xFF101016)),
  ThemePreset('ocean', '海盐蓝', Color(0xFF5EC8E5), Color(0xFF0E161D)),
  ThemePreset('mint', '薄荷绿', Color(0xFF69D3B1), Color(0xFF0E1815)),
  ThemePreset('coral', '珊瑚橙', Color(0xFFFF967A), Color(0xFF1B1313)),
  ThemePreset('sunset', '落日金', Color(0xFFFFC857), Color(0xFF1A1710)),
  ThemePreset('rose', '玫瑰粉', Color(0xFFF28AB2), Color(0xFF1A1118)),
];

class LyricPosterApp extends StatefulWidget {
  const LyricPosterApp({super.key, this.updates});

  final UpdateController? updates;

  @override
  State<LyricPosterApp> createState() => _LyricPosterAppState();
}

class _LyricPosterAppState extends State<LyricPosterApp> {
  late final PosterController controller;
  late final AppLifecycleListener lifecycle;
  late final UpdateController updates;

  @override
  void initState() {
    super.initState();
    controller = PosterController()..loadPreferences();
    updates = widget.updates ?? UpdateController();
    lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(controller.saveDraft()),
      onPause: () => unawaited(controller.saveDraft()),
      onExitRequested: () async {
        await controller.saveDraft();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    lifecycle.dispose();
    controller.dispose();
    if (widget.updates == null) updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: '词笺 · Lyric Poster',
      debugShowCheckedModeBanner: false,
      theme: controller.appTheme,
      home: PosterWorkspace(controller: controller, updates: updates),
    ),
  );
}

class PosterController extends ChangeNotifier {
  PosterController({NeteaseClient? client, HistoryStore? history})
    : client = client ?? NeteaseClient(),
      history = history ?? HistoryStore() {
    fonts.addListener(_fontChanged);
    this.history.addListener(_historyChanged);
  }

  final fonts = FontLibrary();
  final HistoryStore history;
  bool historyReady = false, savingDraft = false;
  String? historyError;
  String? activeDraftId;
  String? activePlaylistSource;
  bool draftDirty = false;
  Timer? _draftTimer;
  int _draftRevision = 0, _selectionRevision = 0;
  final _trackDraftIds = Expando<String>();
  Future<void> _draftWrite = Future.value();
  bool _disposed = false;
  void _historyChanged() {
    if (!_disposed) notifyListeners();
  }

  void _fontChanged() {
    if (_disposed) return;
    lyricPage = lyricPage.clamp(0, lyricPageCount - 1);
    _designChanged();
  }

  final NeteaseClient client;
  final tracks = <Track>[];
  final searchResults = <Track>[];
  final stickers = <PosterSticker>[];
  Track? selected;
  bool isLoading = false, isSearching = false;
  String? error, searchError;
  String playlistName = '未导入歌单';
  String searchQuery = '';
  int currentTab = 0, lyricPage = 0;
  int maxLinesPerPage = defaultMaxLinesPerPage;
  String layout = '居中', dimensions = 'A4 竖版';
  Color background = Colors.white, accent = const Color(0xFF7354AA);
  Color defaultBackground = Colors.white;
  bool useAlbumCover = false;
  String? topWatermark;
  String bottomWatermark = '词笺 · LYRIC POSTER';
  bool showTopWatermark = true,
      showBottomWatermark = true,
      showTopDecoration = true;
  double titleSize = 30, lyricSize = 15, overlay = .46;
  Uint8List? backgroundImage;
  String? backgroundImageName;
  Offset backgroundOffset = Offset.zero;
  double backgroundScale = 1;
  double _backgroundGestureScale = 1;
  final _stickerGestureScales = <int, double>{};
  String themeId = 'violet';
  bool showPageNumbers = true, rememberLastDesign = true;

  static const defaultMaxLinesPerPage = 24;
  static const paperSizes = [
    'A4 竖版',
    'A4 横版',
    'A5 竖版',
    'A5 横版',
    'A6 竖版',
    'A3 竖版',
    'A3 横版',
    'Letter 竖版',
    'Letter 横版',
    '正方形',
    '16:9 横版',
  ];

  ThemeData get appTheme {
    final preset = themePresets.firstWhere(
      (item) => item.id == themeId,
      orElse: () => themePresets.first,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.seed,
      brightness: Brightness.dark,
    );
    final theme = ThemeData(
      fontFamily: appFontFamily,
      fontFamilyFallback: chineseFontFallback,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: preset.scaffold,
      cardTheme: CardThemeData(
        color: Color.alphaBlend(
          Colors.white.withValues(alpha: .025),
          preset.scaffold,
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color.alphaBlend(
          Colors.white.withValues(alpha: .055),
          preset.scaffold,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
    return theme.copyWith(
      textTheme: appTextTheme(theme.textTheme),
      primaryTextTheme: appTextTheme(theme.primaryTextTheme),
    );
  }

  List<String> get lyricLines {
    final value = selected?.lyrics.trim() ?? '';
    if (value.isEmpty) return const ['把喜欢的句子', '留在这一页'];
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
  }

  PosterDocument? get document => selected == null
      ? null
      : PosterDocument(
          track: selected!,
          layout: layout,
          dimensions: dimensions,
          titleSize: titleSize,
          lyricSize: lyricSize,
          background: background,
          accent: accent,
          overlay: overlay,
          backgroundImage: backgroundImage,
          backgroundOffset: backgroundOffset,
          backgroundScale: backgroundScale,
          stickers: stickers,
          showPageNumbers: showPageNumbers,
          useAlbumCover: useAlbumCover,
          fontFamily: fonts.selectedFamily,
          maxLinesPerPage: maxLinesPerPage,
          topWatermark: topWatermark,
          bottomWatermark: bottomWatermark,
          showTopWatermark: showTopWatermark,
          showBottomWatermark: showBottomWatermark,
          showTopDecoration: showTopDecoration,
        );

  int get lyricPageCount => document?.pages.length ?? 1;
  List<String> get currentLyricPageLines =>
      document?.pages[lyricPage.clamp(0, lyricPageCount - 1)].trim().split(
        '\n',
      ) ??
      lyricLines;

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    themeId = prefs.getString('themeId') ?? themeId;
    dimensions = prefs.getString('defaultDimensions') ?? dimensions;
    maxLinesPerPage = (prefs.getInt('maxLinesPerPage') ?? maxLinesPerPage)
        .clamp(8, 40);
    final savedColor = prefs.getInt('defaultBackground');
    final migratedBackground = prefs.getInt('backgroundDefaultsVersion') == 2;
    // Upgrade the untouched legacy dark background to the new paper default.
    if (savedColor != null &&
        (migratedBackground || savedColor != 0xFF17151F)) {
      defaultBackground = Color(savedColor);
      background = defaultBackground;
    }
    if (!migratedBackground) {
      await prefs.setInt('defaultBackground', defaultBackground.toARGB32());
      await prefs.setInt('backgroundDefaultsVersion', 2);
      if (_disposed) return;
    }
    showPageNumbers = prefs.getBool('showPageNumbers') ?? showPageNumbers;
    rememberLastDesign =
        prefs.getBool('rememberLastDesign') ?? rememberLastDesign;
    notifyListeners();
    await fonts.restore();
    try {
      await history.load();
      if (_disposed) return;
      historyReady = true;
      if (selected != null) _designChanged();
    } catch (_) {
      historyError = '历史记录读取失败，请检查本地存储是否可用。';
    }
    if (!_disposed) notifyListeners();
  }

  void _designChanged() {
    if (_disposed) return;
    if (selected != null) {
      draftDirty = true;
      _draftRevision++;
      if (historyReady) {
        activeDraftId ??=
            _trackDraftIds[selected!] ??
            'draft-${DateTime.now().microsecondsSinceEpoch}';
        _trackDraftIds[selected!] = activeDraftId;
        _draftTimer?.cancel();
        _draftTimer = Timer(
          const Duration(milliseconds: 500),
          () => unawaited(saveDraft()),
        );
      }
    }
    notifyListeners();
  }

  Map<String, dynamic> _draftSnapshot() => {
    'version': 1,
    'track': trackToMap(selected!),
    'layout': layout,
    'dimensions': dimensions,
    'titleSize': titleSize,
    'lyricSize': lyricSize,
    'topWatermark': topWatermark,
    'bottomWatermark': bottomWatermark,
    'showTopWatermark': showTopWatermark,
    'showBottomWatermark': showBottomWatermark,
    'showTopDecoration': showTopDecoration,
    'maxLinesPerPage': maxLinesPerPage,
    'background': background.toARGB32(),
    'accent': accent.toARGB32(),
    'overlay': overlay,
    'useAlbumCover': useAlbumCover,
    'backgroundImage': backgroundImage,
    'backgroundImageName': backgroundImageName,
    'backgroundX': backgroundOffset.dx,
    'backgroundY': backgroundOffset.dy,
    'backgroundScale': backgroundScale,
    'fontFamily': fonts.selectedFamily,
    'showPageNumbers': showPageNumbers,
    'lyricPage': lyricPage,
    'stickers': [
      for (final item in stickers)
        {
          'bytes': item.bytes,
          'x': item.position.dx,
          'y': item.position.dy,
          'size': item.size,
          'scale': item.scale,
          'rotation': item.rotation,
        },
    ],
  };

  Future<void> saveDraft() async {
    _draftTimer?.cancel();
    if (!historyReady || selected == null || !draftDirty) {
      await _draftWrite;
      return;
    }
    final id = activeDraftId ??=
        'draft-${DateTime.now().microsecondsSinceEpoch}';
    final revision = _draftRevision;
    final snapshot = _draftSnapshot();
    // Mark this revision queued immediately so concurrent lifecycle callbacks
    // do not queue duplicate saves. New edits set the flag again.
    draftDirty = false;
    savingDraft = true;
    if (!_disposed) notifyListeners();
    final write = _draftWrite.then((_) async {
      try {
        await history.saveDraft(id, snapshot);
        if (_disposed) return;
        historyError = null;
      } catch (_) {
        if (_disposed) return;
        if (activeDraftId == id && _draftRevision == revision) {
          draftDirty = true;
        }
        historyError = '草稿保存失败，请检查本地存储空间后重试。';
      }
    });
    _draftWrite = write;
    await write;
    if (_disposed) return;
    if (identical(_draftWrite, write)) savingDraft = false;
    notifyListeners();
  }

  Future<void> openPlaylist(HistoryEntry entry) async {
    try {
      final data = await history.readEntry(entry.id);
      await saveDraft();
      if (_disposed) return;
      final restored = (data['tracks'] as List)
          .map((raw) => trackFromMap(Map<String, dynamic>.from(raw as Map)))
          .toList();
      tracks
        ..clear()
        ..addAll(restored);
      searchResults.clear();
      playlistName = entry.title;
      activePlaylistSource = entry.source;
      error = null;
      historyError = null;
      if (restored.isNotEmpty) {
        await selectTrack(restored.first, fetchLyrics: false);
      }
      currentTab = 1;
      notifyListeners();
    } catch (_) {
      historyError = '无法打开这份歌单记录，记录文件可能已丢失。';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> openDraft(HistoryEntry entry) async {
    final request = ++_selectionRevision;
    try {
      await saveDraft();
      final data = await history.readEntry(entry.id);
      if (_disposed || request != _selectionRevision) return;
      final track = trackFromMap(
        Map<String, dynamic>.from(data['track'] as Map),
      );
      // Validate the full snapshot before replacing the current canvas.
      final restoredStickers = [
        for (final raw in data['stickers'] as List)
          PosterSticker(
            bytes: raw['bytes'] as Uint8List,
            position: Offset(
              (raw['x'] as num).toDouble(),
              (raw['y'] as num).toDouble(),
            ),
            size: (raw['size'] as num).toDouble(),
            scale: (raw['scale'] as num).toDouble(),
            rotation: (raw['rotation'] as num).toDouble(),
          ),
      ];
      final family = data['fontFamily'] as String;
      final restoredFont =
          family == defaultFontFamily ||
              fonts.fonts.any((font) => font.family == family)
          ? family
          : defaultFontFamily;
      final restoredLayout = data['layout'] as String;
      final restoredDimensions = data['dimensions'] as String;
      final restoredTitleSize = (data['titleSize'] as num).toDouble();
      final restoredLyricSize = (data['lyricSize'] as num).toDouble();
      final restoredMaxLines =
          (data['maxLinesPerPage'] as int?) ?? defaultMaxLinesPerPage;
      final restoredBackground = Color(data['background'] as int);
      final restoredAccent = Color(data['accent'] as int);
      final restoredOverlay = (data['overlay'] as num).toDouble();
      final restoredImage = data['backgroundImage'] as Uint8List?;
      final restoredImageName = data['backgroundImageName'] as String?;
      final restoredOffset = Offset(
        (data['backgroundX'] as num).toDouble(),
        (data['backgroundY'] as num).toDouble(),
      );
      final restoredScale = (data['backgroundScale'] as num).toDouble();
      final restoredCover = data['useAlbumCover'] as bool;
      final restoredNumbers = data['showPageNumbers'] as bool;
      final restoredPage = data['lyricPage'] as int;
      final restoredTopWatermark = data['topWatermark'] as String?;
      final restoredBottomWatermark =
          data['bottomWatermark'] as String? ?? '词笺 · LYRIC POSTER';
      selected = track;
      tracks.removeWhere(
        (item) =>
            identical(item, track) ||
            item.id == track.id &&
                item.title == track.title &&
                item.artist == track.artist,
      );
      tracks.insert(0, track);
      layout = restoredLayout;
      dimensions = restoredDimensions;
      titleSize = restoredTitleSize;
      lyricSize = restoredLyricSize;
      maxLinesPerPage = restoredMaxLines.clamp(8, 40);
      topWatermark = restoredTopWatermark;
      bottomWatermark = restoredBottomWatermark;
      showTopWatermark = data['showTopWatermark'] as bool? ?? true;
      showBottomWatermark = data['showBottomWatermark'] as bool? ?? true;
      showTopDecoration = data['showTopDecoration'] as bool? ?? true;
      background = restoredBackground;
      accent = restoredAccent;
      overlay = restoredOverlay;
      useAlbumCover = restoredCover;
      backgroundImage = restoredImage;
      backgroundImageName = restoredImageName;
      backgroundOffset = restoredOffset;
      backgroundScale = restoredScale;
      showPageNumbers = restoredNumbers;
      stickers
        ..clear()
        ..addAll(restoredStickers);
      _draftTimer?.cancel();
      activeDraftId = entry.id;
      _trackDraftIds[track] = entry.id;
      fonts.selectedFamily = restoredFont;
      lyricPage = restoredPage.clamp(0, lyricPageCount - 1);
      draftDirty = false;
      historyError = family == restoredFont ? null : '原字体不可用，已使用默认中文字体。';
      currentTab = 1;
      notifyListeners();
    } catch (_) {
      historyError = '无法打开这份海报草稿，记录文件可能已损坏。';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> deleteHistory(
    HistoryEntry entry, {
    required bool playlist,
  }) async {
    try {
      await saveDraft();
      await history.delete(entry, playlist: playlist);
      if (!playlist && activeDraftId == entry.id) {
        _draftTimer?.cancel();
        activeDraftId = null;
        if (selected != null) _trackDraftIds[selected!] = null;
        draftDirty = false;
      }
      historyError = null;
    } catch (_) {
      historyError = '删除失败，请重试。';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) await prefs.setString(key, value);
    if (value is int) await prefs.setInt(key, value);
    if (value is bool) await prefs.setBool(key, value);
  }

  Future<void> importPlaylist(String input) async {
    if (isLoading) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final result = await client.fetchPlaylist(input);
      await saveDraft();
      if (_disposed || draftDirty && historyReady) return;
      tracks
        ..clear()
        ..addAll(result);
      searchResults.clear();
      final id = client.parsePlaylistId(input)!;
      playlistName = client.playlistTitle ?? '网易云歌单 $id';
      activePlaylistSource = 'https://music.163.com/playlist?id=$id';
      if (tracks.isNotEmpty) await selectTrack(tracks.first);
      try {
        await history.savePlaylist(id, playlistName, result);
      } catch (_) {
        historyError = '歌单已导入，但保存历史记录失败，请检查本地存储空间。';
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> searchSongs(String input) async {
    final query = input.trim();
    searchQuery = query;
    if (query.isEmpty) {
      searchResults.clear();
      searchError = null;
      notifyListeners();
      return;
    }
    isSearching = true;
    searchError = null;
    notifyListeners();
    try {
      searchResults
        ..clear()
        ..addAll(await client.searchSongs(query));
    } catch (e) {
      searchError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  Future<void> addSearchResult(Track track) async {
    Track? existing;
    for (final item in tracks) {
      if (item.id == track.id) {
        existing = item;
        break;
      }
    }
    final item = existing ?? track;
    if (existing == null) tracks.add(track);
    await selectTrack(item);
    currentTab = 1;
    notifyListeners();
  }

  Future<void> selectTrack(Track track, {bool fetchLyrics = true}) async {
    if (identical(selected, track)) return;
    final request = ++_selectionRevision;
    await saveDraft();
    if (_disposed ||
        request != _selectionRevision ||
        draftDirty && historyReady) {
      return;
    }
    if (!_acceptTrack(track)) return;
    activeDraftId = _trackDraftIds[track];
    lyricPage = 0;
    _designChanged();
    if (!fetchLyrics || track.lyrics.isNotEmpty || track.id.isEmpty) return;
    try {
      track.lyrics = await client.fetchLyrics(track.id);
      if (!_disposed && identical(selected, track)) _designChanged();
    } catch (_) {}
  }

  Future<void> addManualTrack() async {
    await saveDraft();
    if (_disposed || draftDirty && historyReady) return;
    final track = Track(
      id: '',
      title: '新歌曲',
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
    );
    if (!_acceptTrack(track)) return;
    tracks.insert(0, track);
    activeDraftId = null;
    lyricPage = 0;
    currentTab = 1;
    error = null;
    _designChanged();
  }

  bool _acceptTrack(Track track) {
    final previous = selected;
    selected = track;
    try {
      document;
      return true;
    } catch (_) {
      selected = previous;
      historyError = '当前纸张放不下此歌曲，请先减小字号或增大纸张。';
      notifyListeners();
      return false;
    }
  }

  bool updateSelected({String? title, String? artist, String? lyrics}) {
    final track = selected;
    if (track == null) return false;
    final previousTitle = track.title;
    final previousArtist = track.artist;
    final previousLyrics = track.lyrics;
    if (title != null) track.title = title;
    if (artist != null) track.artist = artist;
    if (lyrics != null) track.lyrics = lyrics;
    try {
      document;
    } catch (_) {
      track.title = previousTitle;
      track.artist = previousArtist;
      track.lyrics = previousLyrics;
      return false;
    }
    if (lyricPage >= lyricPageCount) lyricPage = lyricPageCount - 1;
    _designChanged();
    return true;
  }

  void setLyricPage(int page) {
    lyricPage = page.clamp(0, lyricPageCount - 1);
    _designChanged();
  }

  void setTab(int value) {
    currentTab = value;
    notifyListeners();
  }

  bool setLayout(String value) {
    final previous = layout;
    layout = value;
    try {
      document;
    } catch (_) {
      layout = previous;
      return false;
    }
    lyricPage = lyricPage.clamp(0, lyricPageCount - 1);
    _designChanged();
    return true;
  }

  bool setTitleSize(double value) {
    if (!value.isFinite || value < 4 || value > 144) return false;
    final previous = titleSize;
    titleSize = value;
    try {
      document;
    } catch (_) {
      titleSize = previous;
      return false;
    }
    lyricPage = lyricPage.clamp(0, lyricPageCount - 1);
    _designChanged();
    return true;
  }

  bool setLyricSize(double value) {
    if (!value.isFinite || value < 4 || value > 96) return false;
    final previous = lyricSize;
    lyricSize = value;
    try {
      document;
    } catch (_) {
      lyricSize = previous;
      return false;
    }
    lyricPage = lyricPage.clamp(0, lyricPageCount - 1);
    _designChanged();
    return true;
  }

  void updateWatermarks({
    String? top,
    String? bottom,
    bool? showTop,
    bool? showBottom,
    bool? decoration,
    bool resetTop = false,
  }) {
    if (resetTop) {
      topWatermark = null;
    } else if (top != null) {
      topWatermark = top;
    }
    if (bottom != null) bottomWatermark = bottom;
    if (showTop != null) showTopWatermark = showTop;
    if (showBottom != null) showBottomWatermark = showBottom;
    if (decoration != null) showTopDecoration = decoration;
    _designChanged();
  }

  Future<void> setMaxLinesPerPage(int value, {bool persist = true}) async {
    maxLinesPerPage = value.clamp(8, 40);
    lyricPage = lyricPage.clamp(0, lyricPageCount - 1);
    _designChanged();
    if (persist) await _save('maxLinesPerPage', maxLinesPerPage);
  }

  Future<void> saveMaxLinesPerPagePreference() =>
      _save('maxLinesPerPage', maxLinesPerPage);

  void setOverlay(double value) {
    overlay = value;
    _designChanged();
  }

  void setBackground(Color value, {bool saveAsDefault = false}) {
    background = value;
    if (saveAsDefault) {
      defaultBackground = value;
      _save('defaultBackground', value.toARGB32());
      _save('backgroundDefaultsVersion', 2);
    }
    _designChanged();
  }

  void setAccent(Color value) {
    accent = value;
    _designChanged();
  }

  bool setDimensions(String value, {bool saveAsDefault = false}) {
    if (!paperSizes.contains(value)) return false;
    final previous = dimensions;
    dimensions = value;
    try {
      document;
    } catch (_) {
      dimensions = previous;
      return false;
    }
    lyricPage = lyricPage.clamp(0, lyricPageCount - 1);
    if (saveAsDefault) _save('defaultDimensions', value);
    _designChanged();
    return true;
  }

  void setTheme(String value) {
    themeId = value;
    _save('themeId', value);
    notifyListeners();
  }

  void setShowPageNumbers(bool value) {
    showPageNumbers = value;
    _save('showPageNumbers', value);
    _designChanged();
  }

  void setRememberLastDesign(bool value) {
    rememberLastDesign = value;
    _save('rememberLastDesign', value);
    notifyListeners();
  }

  void setBackgroundImage(Uint8List bytes, String name) {
    backgroundImage = bytes;
    backgroundImageName = name;
    backgroundOffset = Offset.zero;
    backgroundScale = 1;
    _designChanged();
  }

  void clearBackgroundImage() {
    backgroundImage = null;
    backgroundImageName = null;
    backgroundOffset = Offset.zero;
    backgroundScale = 1;
    _designChanged();
  }

  void moveBackground(Offset delta) {
    backgroundOffset += delta;
    _designChanged();
  }

  void scaleBackground(double factor) {
    backgroundScale = (backgroundScale * factor).clamp(.45, 4.0);
    _designChanged();
  }

  void beginBackgroundGesture() {
    _backgroundGestureScale = backgroundScale;
  }

  void updateBackgroundGesture(Offset delta, double scale) {
    backgroundOffset += delta;
    backgroundScale = (_backgroundGestureScale * scale).clamp(.45, 4.0);
    _designChanged();
  }

  void addSticker(Uint8List bytes) {
    final size = PosterDocument.paperSize(dimensions);
    stickers.add(
      PosterSticker(
        bytes: bytes,
        position: Offset(size.width * .08, size.height * .18),
      ),
    );
    _designChanged();
  }

  void moveSticker(int index, Offset delta) {
    if (index < 0 || index >= stickers.length) return;
    stickers[index].position += delta;
    _designChanged();
  }

  void scaleSticker(int index, double factor) {
    if (index < 0 || index >= stickers.length) return;
    stickers[index].scale = (stickers[index].scale * factor).clamp(.25, 4.0);
    _designChanged();
  }

  void beginStickerGesture(int index) {
    if (index >= 0 && index < stickers.length) {
      _stickerGestureScales[index] = stickers[index].scale;
    }
  }

  void updateStickerGesture(int index, Offset delta, double scale) {
    if (index < 0 || index >= stickers.length) return;
    stickers[index].position += delta;
    stickers[index].scale =
        ((_stickerGestureScales[index] ?? stickers[index].scale) * scale).clamp(
          .25,
          4.0,
        );
    _designChanged();
  }

  void removeLastSticker() {
    if (stickers.isNotEmpty) stickers.removeLast();
    _designChanged();
  }

  void setUseAlbumCover(bool value) {
    useAlbumCover = value;
    _designChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    _draftTimer?.cancel();
    history.removeListener(_historyChanged);
    history.dispose();
    fonts.removeListener(_fontChanged);
    fonts.dispose();
    client.close();
    super.dispose();
  }
}

class PosterWorkspace extends StatefulWidget {
  const PosterWorkspace({required this.controller, this.updates, super.key});
  final PosterController controller;
  final UpdateController? updates;

  @override
  State<PosterWorkspace> createState() => _PosterWorkspaceState();
}

class _PosterWorkspaceState extends State<PosterWorkspace> {
  PosterController get controller => widget.controller;
  final previewKey = GlobalKey();
  final link = TextEditingController();
  final search = TextEditingController();
  bool exporting = false;
  String editorSection = '排版与纸张';
  bool toolsVisible = true;
  static const editorSections = ['排版与纸张', '文字与字体', '背景与颜色', '图片与贴纸', '上下水印'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(checkStartupUpdate());
    });
  }

  Future<void> checkStartupUpdate() async {
    final updates = widget.updates;
    if (updates == null) return;
    await updates.check();
    if (!mounted || updates.error != null || !updates.updateAvailable) return;
    await showAppUpdateDialog(context, updates.latestRelease!);
  }

  @override
  void dispose() {
    link.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset(
                  'assets/icons/app_icon.png',
                  width: 28,
                  height: 28,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 10),
                const Text('词笺', style: TextStyle(fontWeight: FontWeight.w400)),
                if (constraints.maxWidth >= 560) const SizedBox(width: 10),
                if (constraints.maxWidth >= 560)
                  const Text(
                    'LYRIC POSTER',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: Colors.white54,
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '设置',
                onPressed: () => controller.setTab(4),
                icon: const Icon(Icons.settings_outlined),
              ),
              if (controller.selected != null)
                FilledButton.icon(
                  onPressed: () => controller.setTab(2),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('导出海报'),
                ),
              const SizedBox(width: 16),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    buildRail(),
                    if (controller.currentTab == 0)
                      SizedBox(width: 320, child: buildLibrary()),
                    Expanded(child: buildAnimatedMain(context)),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: buildAnimatedMain(context)),
                    NavigationBar(
                      selectedIndex: controller.currentTab,
                      onDestinationSelected: controller.setTab,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.library_music),
                          label: '歌单',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.tune_outlined),
                          selectedIcon: Icon(Icons.tune),
                          label: '设计',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.ios_share_outlined),
                          selectedIcon: Icon(Icons.ios_share),
                          label: '导出',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.history_outlined),
                          selectedIcon: Icon(Icons.history),
                          label: '历史',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: '设置',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.info_outline),
                          selectedIcon: Icon(Icons.info),
                          label: '关于',
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    ),
  );

  Widget buildAnimatedMain(BuildContext context) => AppMotion(
    key: const ValueKey('workspace-motion'),
    identity: controller.currentTab,
    child: buildMain(context),
  );

  Widget buildRail() => NavigationRail(
    selectedIndex: controller.currentTab,
    onDestinationSelected: controller.setTab,
    backgroundColor: Colors.black.withValues(alpha: .12),
    labelType: NavigationRailLabelType.all,
    destinations: const [
      NavigationRailDestination(
        icon: Icon(Icons.library_music_outlined),
        selectedIcon: Icon(Icons.library_music),
        label: Text('歌单'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: Text('设计'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.ios_share_outlined),
        selectedIcon: Icon(Icons.ios_share),
        label: Text('导出'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: Text('历史'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('设置'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.info_outline),
        selectedIcon: Icon(Icons.info),
        label: Text('关于'),
      ),
    ],
  );

  Widget buildLibrary() => Material(
    color: Colors.black.withValues(alpha: .08),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '我的音乐',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 5),
          Text(
            controller.playlistName,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索歌曲、歌手',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        search.clear();
                        controller.searchSongs('');
                      },
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: controller.searchSongs,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: controller.isSearching
                  ? null
                  : () => controller.searchSongs(search.text),
              icon: controller.isSearching
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: const Text('搜索网易云歌曲'),
            ),
          ),
          if (controller.searchError != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.searchError!,
              style: const TextStyle(color: Color(0xFFFF9E9E), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: controller.addManualTrack,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('手动新建歌曲'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
          ),
          if (controller.searchResults.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('搜索结果', style: TextStyle(fontWeight: FontWeight.w400)),
            const SizedBox(height: 5),
            SizedBox(
              height: 190,
              child: buildTrackList(
                controller.searchResults,
                searchResult: true,
              ),
            ),
            const Divider(height: 24),
          ],
          Text(
            controller.searchResults.isNotEmpty ? '我的歌单' : '歌曲列表',
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: controller.tracks.isEmpty
                ? const Center(
                    child: Text(
                      '导入歌单或搜索歌曲\n歌曲会显示在这里',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, height: 1.6),
                    ),
                  )
                : buildTrackList(controller.tracks),
          ),
        ],
      ),
    ),
  );

  Widget buildTrackList(
    List<Track> items, {
    bool searchResult = false,
  }) => ListView.separated(
    itemCount: items.length,
    separatorBuilder: (_, _) => const SizedBox(height: 4),
    itemBuilder: (context, index) {
      final track = items[index];
      final active = identical(track, controller.selected);
      return ListTile(
        dense: true,
        selected: active,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: .18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        leading: cover(track.coverUrl, 36),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        trailing: searchResult
            ? IconButton(
                tooltip: '添加到歌单',
                icon: const Icon(Icons.add_circle_outline, size: 19),
                onPressed: () => controller.addSearchResult(track),
              )
            : null,
        onTap: () {
          if (searchResult) {
            controller.addSearchResult(track);
          } else {
            controller.selectTrack(track);
            controller.setTab(1);
          }
        },
      );
    },
  );

  Widget buildMain(BuildContext context) {
    if (controller.currentTab == 0) return buildImport(context);
    if (controller.currentTab == 2) return buildExport(context);
    if (controller.currentTab == 4) return buildSettings(context);
    if (controller.currentTab == 3) return buildHistory(context);
    if (controller.currentTab == 5) return AboutPage(updates: widget.updates);
    return buildDesign(context);
  }

  Widget buildHistory(BuildContext context) => DefaultTabController(
    length: 2,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '历史记录',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 6),
          const Text(
            '歌单保存在本机；海报草稿会自动保存，点击即可继续编辑。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          if (controller.historyError != null) ...[
            const SizedBox(height: 10),
            Text(
              controller.historyError!,
              style: const TextStyle(color: Color(0xFFFFAB91)),
            ),
          ],
          const SizedBox(height: 14),
          TabBar(
            tabs: [
              Tab(text: '海报草稿 (${controller.history.drafts.length})'),
              Tab(text: '导入歌单 (${controller.history.playlists.length})'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                historyList(controller.history.drafts, playlist: false),
                historyList(controller.history.playlists, playlist: true),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget historyList(List<HistoryEntry> entries, {required bool playlist}) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          playlist ? '还没有歌单历史\n成功导入的歌单会自动出现在这里' : '还没有海报草稿\n开始编辑后将自动保存到这里',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, height: 1.8),
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final date = entry.updatedAt.toLocal();
        final updated =
            '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      playlist ? Icons.queue_music : Icons.article_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w400),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除记录',
                      onPressed: () =>
                          confirmDeleteHistory(entry, playlist: playlist),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ],
                ),
                Text(
                  '${entry.subtitle}${playlist ? ' · ${entry.trackCount} 首' : ''}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '保存于 $updated',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => playlist
                          ? controller.openPlaylist(entry)
                          : controller.openDraft(entry),
                      icon: Icon(
                        playlist ? Icons.folder_open : Icons.edit_outlined,
                        size: 18,
                      ),
                      label: Text(playlist ? '打开已保存歌单' : '继续编辑'),
                    ),
                    if (playlist)
                      OutlinedButton.icon(
                        onPressed: controller.isLoading
                            ? null
                            : () async {
                                await controller.importPlaylist(entry.source);
                                if (context.mounted) {
                                  if (controller.error == null) {
                                    controller.setTab(0);
                                  }
                                  toast(context, controller.error ?? '歌单已重新获取');
                                }
                              },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('联网更新'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> confirmDeleteHistory(
    HistoryEntry entry, {
    required bool playlist,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除记录'),
        content: Text(
          '删除“${entry.title}”？${playlist ? '已保存的海报草稿会保留。' : '草稿中的背景图和贴纸也会一起删除。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteHistory(entry, playlist: playlist);
    }
  }

  Widget buildImport(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            Text(
              '把喜欢的歌，做成一张海报。',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 8),
            const Text(
              '粘贴网易云公开歌单，自动获取歌曲和歌词；也可以搜索单曲开始排版。',
              style: TextStyle(color: Colors.white60, fontSize: 15),
            ),
            const SizedBox(height: 30),
            if (MediaQuery.sizeOf(context).width < 980) ...[
              buildMobileSearch(),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '导入网易云歌单',
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '支持歌单链接、分享文本或纯数字歌单 ID',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: link,
                            decoration: const InputDecoration(
                              hintText:
                                  '例如 https://music.163.com/playlist?id=...',
                            ),
                            onSubmitted: (_) =>
                                controller.importPlaylist(link.text),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: controller.isLoading
                              ? null
                              : () => controller.importPlaylist(link.text),
                          icon: controller.isLoading
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download, size: 18),
                          label: const Text('开始导入'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (controller.error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        controller.error!,
                        style: const TextStyle(
                          color: Color(0xFFFF9E9E),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (MediaQuery.sizeOf(context).width < 980) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '我的音乐',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        controller.playlistName,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (controller.tracks.isEmpty)
                        const Text('导入歌单或搜索歌曲，歌曲会显示在这里。')
                      else
                        SizedBox(
                          height: 280,
                          child: buildTrackList(controller.tracks),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: feature(Icons.search, '搜索单曲', '直接搜索网易云歌曲，加入当前工作区。'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: feature(Icons.touch_app, '画布直编', '点击标题、歌手或歌词即可编辑。'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: feature(
                    Icons.print_outlined,
                    '适合打印',
                    '多种纸张尺寸，导出高清 PNG 或 PDF。',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: controller.addManualTrack,
              icon: const Icon(Icons.add),
              label: const Text('不导入歌单，直接新建一张海报'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget buildMobileSearch() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('搜索网易云歌曲', style: TextStyle(fontWeight: FontWeight.w400)),
          const SizedBox(height: 10),
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: '搜索歌名或歌手',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: controller.searchSongs,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: controller.isSearching
                  ? null
                  : () => controller.searchSongs(search.text),
              icon: controller.isSearching
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('搜索'),
            ),
          ),
          if (controller.searchResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '搜索结果',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 190,
              child: buildTrackList(
                controller.searchResults,
                searchResult: true,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget feature(IconData icon, String title, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: controller.accent, size: 23),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w400)),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white54,
              height: 1.35,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );

  void selectEditorSection(String section) => setState(() {
    editorSection = section;
    toolsVisible = true;
  });

  void changePaper(String paper, {bool saveAsDefault = false}) {
    if (!controller.setDimensions(paper, saveAsDefault: saveAsDefault)) {
      toast(context, '当前纸张放不下此字号，请先减小标题或歌词字号。');
    }
  }

  Widget buildDesign(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide = constraints.maxWidth >= 760;
      final panel = buildEditorSidebar();
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.historyError ??
                        (controller.selected == null
                            ? '从歌单中选择歌曲开始设计'
                            : controller.savingDraft
                            ? '正在保存草稿…'
                            : controller.draftDirty
                            ? '等待自动保存…'
                            : '草稿已保存'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
                IconButton(
                  tooltip: toolsVisible ? '收起设计侧栏' : '展开设计侧栏',
                  onPressed: () => setState(() => toolsVisible = !toolsVisible),
                  icon: Icon(
                    toolsVisible ? Icons.view_sidebar_outlined : Icons.tune,
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      controller.selected == null || controller.savingDraft
                      ? null
                      : () async {
                          await controller.saveDraft();
                          if (context.mounted) {
                            toast(
                              context,
                              controller.historyError ?? '草稿已保存到历史记录',
                            );
                          }
                        },
                  icon: const Icon(Icons.save_outlined, size: 17),
                  label: const Text('保存草稿'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: sideBySide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: previewPanel()),
                        if (toolsVisible) ...[
                          const SizedBox(width: 12),
                          SizedBox(width: 350, child: panel),
                        ],
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, available) => Column(
                        children: [
                          Expanded(child: previewPanel()),
                          if (toolsVisible) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: (available.maxHeight * .54).clamp(0, 340),
                              child: panel,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget buildEditorSidebar() => Card(
    key: const ValueKey('design-sidebar'),
    child: LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.all(constraints.maxHeight < 180 ? 8 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxHeight < 230)
              DropdownButton<String>(
                key: const ValueKey('compact-editor-sections'),
                value: editorSection,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final section in editorSections)
                    DropdownMenuItem(value: section, child: Text(section)),
                ],
                onChanged: (section) {
                  if (section != null) selectEditorSection(section);
                },
              )
            else
              Wrap(
                key: const ValueKey('editor-sections'),
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final section in editorSections)
                    ChoiceChip(
                      key: ValueKey('editor-section-$section'),
                      label: Text(
                        section,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: editorSection == section,
                      onSelected: (_) => selectEditorSection(section),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            const Divider(height: 18),
            Expanded(
              child: AppMotion(
                key: const ValueKey('editor-motion'),
                identity: editorSection,
                child: SingleChildScrollView(
                  key: PageStorageKey('editor-$editorSection'),
                  child: switch (editorSection) {
                    '文字与字体' => buildTextTools(),
                    '背景与颜色' => buildColorTools(),
                    '图片与贴纸' => buildImageTools(),
                    '上下水印' => buildWatermarkTools(),
                    _ => buildLayoutTools(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget buildTextTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      buildFontControls(),
      const SizedBox(height: 18),
      if (controller.selected case final track?) ...[
        LiveTextField(
          key: const ValueKey('edit-song-title'),
          label: '歌曲标题',
          value: track.title,
          onChanged: (text) => controller.updateSelected(title: text),
        ),
        const SizedBox(height: 12),
        LiveTextField(
          key: const ValueKey('edit-song-artist'),
          label: '歌手',
          value: track.artist,
          onChanged: (text) => controller.updateSelected(artist: text),
        ),
        const SizedBox(height: 12),
        LiveTextField(
          key: const ValueKey('edit-song-lyrics'),
          label: '完整歌词',
          value: track.lyrics,
          maxLines: 12,
          onChanged: (text) => controller.updateSelected(lyrics: text),
        ),
      ],
    ],
  );

  Widget buildColorTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('背景调色盘', style: TextStyle(fontWeight: FontWeight.w400)),
      const SizedBox(height: 12),
      ColorPaletteEditor(
        key: const ValueKey('background-palette'),
        value: controller.background,
        onChanged: controller.setBackground,
      ),
      const Divider(height: 28),
      const Text('强调色', style: TextStyle(fontWeight: FontWeight.w400)),
      const SizedBox(height: 12),
      ColorPresets(value: controller.accent, onChanged: controller.setAccent),
      const SizedBox(height: 10),
      ColorPaletteEditor(
        key: const ValueKey('accent-palette'),
        value: controller.accent,
        onChanged: controller.setAccent,
      ),
    ],
  );

  Widget buildWatermarkTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示上方水印'),
        subtitle: const Text('仅第一页显示'),
        value: controller.showTopWatermark,
        onChanged: (value) => controller.updateWatermarks(showTop: value),
      ),
      LiveTextField(
        key: const ValueKey('edit-top-watermark'),
        label: '上方水印文字',
        value:
            controller.topWatermark ??
            'LYRIC / ${controller.selected?.album.toUpperCase() ?? ''}',
        hint: '留空可隐藏文字',
        onChanged: (text) {
          controller.updateWatermarks(top: text);
          return true;
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => controller.updateWatermarks(resetTop: true),
          child: const Text('恢复为专辑信息'),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示顶部波形装饰'),
        value: controller.showTopDecoration,
        onChanged: (value) => controller.updateWatermarks(decoration: value),
      ),
      const Divider(height: 24),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示下方水印'),
        subtitle: const Text('每页显示'),
        value: controller.showBottomWatermark,
        onChanged: (value) => controller.updateWatermarks(showBottom: value),
      ),
      LiveTextField(
        key: const ValueKey('edit-bottom-watermark'),
        label: '下方水印文字',
        value: controller.bottomWatermark,
        hint: '留空可隐藏文字',
        onChanged: (text) {
          controller.updateWatermarks(bottom: text);
          return true;
        },
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示页码'),
        value: controller.showPageNumbers,
        onChanged: controller.setShowPageNumbers,
      ),
    ],
  );

  Widget animatedPosterPreview() => AppMotion(
    key: const ValueKey('preview-motion'),
    identity: (controller.selected, controller.lyricPage),
    child: RepaintBoundary(
      key: previewKey,
      child: PosterCanvas(controller: controller, onElementTap: editElement),
    ),
  );

  Widget previewPanel() => Card(
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 135) {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: animatedPosterPreview(),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '整页预览',
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                  ),
                  IconButton(
                    tooltip: '上一页',
                    onPressed: controller.lyricPage == 0
                        ? null
                        : () =>
                              controller.setLyricPage(controller.lyricPage - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${controller.lyricPage + 1} / ${controller.lyricPageCount}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  IconButton(
                    tooltip: '下一页',
                    onPressed:
                        controller.lyricPage + 1 >= controller.lyricPageCount
                        ? null
                        : () =>
                              controller.setLyricPage(controller.lyricPage + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: Center(child: animatedPosterPreview())),
              const SizedBox(height: 8),
              Text(
                controller.dimensions,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget buildLayoutTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('版式'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final item in ['居中', '左对齐', '唱片'])
            ChoiceChip(
              label: Text(item),
              selected: controller.layout == item,
              onSelected: (_) {
                if (!controller.setLayout(item)) {
                  toast(context, '当前版式放不下此字号，请先减小标题或歌词字号。');
                }
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('纸张尺寸'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final item in PosterController.paperSizes)
            ChoiceChip(
              label: Text(item),
              selected: controller.dimensions == item,
              onSelected: (_) => changePaper(item),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        '打印字号（1 pt = 1/72 英寸）',
        style: TextStyle(fontSize: 12, color: Colors.white60),
      ),
      const SizedBox(height: 12),
      PointSizeField(
        key: const ValueKey('title-size-input'),
        label: '标题字号',
        value: controller.titleSize,
        max: 144,
        onChanged: controller.setTitleSize,
      ),
      PointSizeField(
        key: const ValueKey('lyric-size-input'),
        label: '歌词字号',
        value: controller.lyricSize,
        max: 96,
        onChanged: controller.setLyricSize,
      ),
      Row(
        children: [
          const SizedBox(
            width: 75,
            child: Text(
              '每页歌词',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              key: const ValueKey('max-lines-per-page'),
              min: 8,
              max: 40,
              divisions: 32,
              value: controller.maxLinesPerPage.toDouble(),
              label: '${controller.maxLinesPerPage} 行',
              onChanged: (value) =>
                  controller.setMaxLinesPerPage(value.round(), persist: false),
              onChangeEnd: (_) => controller.saveMaxLinesPerPagePreference(),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${controller.maxLinesPerPage} 行',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(left: 75),
        child: Text(
          '行数为上限；纸张大小和字号仍会影响实际分页。',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示页码'),
        value: controller.showPageNumbers,
        onChanged: controller.setShowPageNumbers,
      ),
    ],
  );

  Widget buildImageTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: pickBackground,
            icon: const Icon(Icons.wallpaper),
            label: Text(
              controller.backgroundImage == null ? '自定义背景图' : '更换背景图',
            ),
          ),
          if (controller.backgroundImage != null)
            OutlinedButton.icon(
              onPressed: controller.clearBackgroundImage,
              icon: const Icon(Icons.hide_image_outlined),
              label: const Text('移除背景图'),
            ),
          OutlinedButton.icon(
            onPressed: pickSticker,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('添加贴纸图片'),
          ),
          if (controller.stickers.isNotEmpty)
            OutlinedButton.icon(
              onPressed: controller.removeLastSticker,
              icon: const Icon(Icons.delete_outline),
              label: const Text('移除最后贴纸'),
            ),
          OutlinedButton.icon(
            onPressed: () => selectEditorSection('背景与颜色'),
            icon: const Icon(Icons.color_lens_outlined),
            label: const Text('强调色'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('常用背景色'),
      const SizedBox(height: 8),
      ColorPresets(
        value: controller.background,
        onChanged: controller.setBackground,
      ),
      if (controller.selected?.coverUrl.isNotEmpty ?? false)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('使用专辑封面作背景'),
          value: controller.useAlbumCover,
          onChanged: controller.setUseAlbumCover,
        ),
      if (controller.backgroundImage != null) ...[
        const SizedBox(height: 8),
        Text(
          controller.backgroundImageName ?? '自定义背景',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        sliderRow(
          '背景缩放',
          controller.backgroundScale,
          .45,
          4,
          (value) =>
              controller.scaleBackground(value / controller.backgroundScale),
        ),
      ],
      if (controller.stickers.isNotEmpty)
        sliderRow(
          '贴纸缩放',
          controller.stickers.last.scale,
          .25,
          4,
          (value) => controller.scaleSticker(
            controller.stickers.length - 1,
            value / controller.stickers.last.scale,
          ),
        ),
      sliderRow('背景遮罩', controller.overlay, 0, .8, controller.setOverlay),
      const Text(
        '可直接在海报上拖动背景图与贴纸，触屏支持双指缩放。',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    ],
  );

  Widget sliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(
        width: 75,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ),
      Expanded(
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
    ],
  );

  void editElement(PosterElement element) {
    selectEditorSection(switch (element) {
      PosterElement.background => '背景与颜色',
      PosterElement.sticker => '图片与贴纸',
      PosterElement.topWatermark || PosterElement.bottomWatermark => '上下水印',
      _ => '文字与字体',
    });
  }

  Future<void> pickBackground() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isNotEmpty) {
      final file = result.first;
      controller.setBackgroundImage(await file.readAsBytes(), file.name);
    }
  }

  Future<void> pickSticker() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    for (final file in result) {
      controller.addSticker(await file.readAsBytes());
    }
  }

  Future<void> chooseColor({
    required Color initial,
    required ValueChanged<Color> apply,
  }) async {
    final value = await showColorPalette(context, initial);
    if (value != null) apply(value);
  }

  Widget buildFontControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('海报字体', style: TextStyle(fontWeight: FontWeight.w400)),
      const SizedBox(height: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('font-${controller.fonts.selectedFamily}'),
            initialValue: controller.fonts.selectedFamily,
            isExpanded: true,
            items: [
              const DropdownMenuItem(
                value: defaultFontFamily,
                child: Text('思源黑体（默认）'),
              ),
              for (final font in controller.fonts.fonts)
                DropdownMenuItem(
                  value: font.family,
                  child: Text(font.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) controller.fonts.select(value);
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: importFont,
            icon: const Icon(Icons.font_download_outlined),
            label: const Text('导入字体'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        '支持 TTF / OTF，导入后保存在本机；预览和导出使用同一字体。',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    ],
  );

  Future<void> importFont() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        dialogTitle: '导入海报字体',
      );
      if (file == null) return;
      await controller.fonts.importFont(file.name, await file.readAsBytes());
      if (mounted) toast(context, '已导入字体：${controller.fonts.selectedName}');
    } catch (error) {
      if (mounted) {
        toast(
          context,
          '导入失败：${error.toString().replaceFirst('FormatException: ', '')}',
        );
      }
    }
  }

  Widget buildExport(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '导出与打印',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 8),
            const Text(
              '标题仅在第一页显示。PDF 导出全部分页，PNG 导出当前页，均为 300 DPI。',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '画布尺寸',
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PosterController.paperSizes
                          .map(
                            (item) => ChoiceChip(
                              label: Text(item),
                              selected: controller.dimensions == item,
                              onSelected: (_) => changePaper(item),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: controller.selected == null
                                ? null
                                : () => exportPng(context),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('导出当前页 PNG'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: controller.selected == null
                                ? null
                                : () => exportPdf(context),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('导出全部 PDF'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (controller.selected != null)
              SizedBox(
                height: MediaQuery.sizeOf(context).height * .6,
                child: previewPanel(),
              ),
          ],
        ),
      ),
    ),
  );

  Widget buildSettings(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '设置',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 8),
            const Text(
              '常用偏好会保存在本机，下次打开继续使用。',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '软件主题',
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: themePresets
                          .map(
                            (preset) => ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: preset.seed,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(preset.name),
                                ],
                              ),
                              selected: controller.themeId == preset.id,
                              onSelected: (_) => controller.setTheme(preset.id),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '默认设计',
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '默认纸张',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PosterController.paperSizes
                          .map(
                            (item) => ChoiceChip(
                              label: Text(item),
                              selected: controller.dimensions == item,
                              onSelected: (_) =>
                                  changePaper(item, saveAsDefault: true),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '默认背景颜色',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        colorButton(
                          controller.defaultBackground,
                          (_) => chooseColor(
                            initial: controller.defaultBackground,
                            apply: (color) => controller.setBackground(
                              color,
                              saveAsDefault: true,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => chooseColor(
                            initial: controller.defaultBackground,
                            apply: (color) => controller.setBackground(
                              color,
                              saveAsDefault: true,
                            ),
                          ),
                          child: const Text('自定义'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ColorPresets(
                      value: controller.defaultBackground,
                      onChanged: (color) =>
                          controller.setBackground(color, saveAsDefault: true),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: buildFontControls(),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('显示页码'),
                    subtitle: const Text('在海报底部显示当前页 / 总页数'),
                    value: controller.showPageNumbers,
                    onChanged: controller.setShowPageNumbers,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('记住上次设计偏好'),
                    subtitle: const Text('保留主题、默认尺寸和背景色'),
                    value: controller.rememberLastDesign,
                    onChanged: controller.setRememberLastDesign,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget colorButton(Color color, ValueChanged<Color> onTap) => InkWell(
    onTap: () => onTap(color),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white54, width: 1.5),
      ),
    ),
  );

  Future<Uint8List?> capture() async {
    final document = controller.document;
    if (document == null) return null;
    return renderPosterPage(document, controller.lyricPage, context: context);
  }

  Future<List<Uint8List>> capturePages() async {
    final pages = <Uint8List>[];
    final document = controller.document;
    if (document == null) return pages;
    for (var page = 0; page < document.pages.length; page++) {
      if (!mounted) throw StateError('导出已取消');
      pages.add(await renderPosterPage(document, page, context: context));
    }
    return pages;
  }

  Future<void> exportPng(BuildContext context) async {
    if (exporting) return;
    exporting = true;
    toast(context, '正在生成 300 DPI 图片…');
    try {
      final page = controller.lyricPage;
      final bytes = await capture();
      if (bytes == null) return;
      final path = await FilePicker.saveFile(
        dialogTitle: '保存歌词海报',
        fileName: 'lyric-poster-page-${page + 1}.png',
        bytes: bytes,
        mimeType: 'image/png',
      );
      if (context.mounted && path != null) {
        toast(context, '第 ${page + 1} 页 PNG 已保存');
      }
    } catch (error) {
      if (context.mounted) toast(context, '导出失败：$error');
    } finally {
      exporting = false;
    }
  }

  Future<void> exportPdf(BuildContext context) async {
    if (exporting) return;
    exporting = true;
    toast(context, '正在生成全部歌词页面…');
    try {
      final pageSize = controller.document?.size;
      if (pageSize == null) return;
      final pages = await capturePages();
      if (pages.isEmpty) return;
      final document = pw.Document();
      for (final png in pages) {
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pageSize.width, pageSize.height),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
          ),
        );
      }
      final bytes = await document.save();
      final path = await FilePicker.saveFile(
        dialogTitle: '保存歌词海报 PDF',
        fileName: 'lyric-poster.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (context.mounted && path != null) {
        toast(context, '已保存 ${pages.length} 页 PDF');
      }
    } catch (error) {
      if (context.mounted) toast(context, '导出失败：$error');
    } finally {
      exporting = false;
    }
  }

  void toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
}

class PosterCanvas extends StatelessWidget {
  const PosterCanvas({required this.controller, this.onElementTap, super.key});
  final PosterController controller;
  final ValueChanged<PosterElement>? onElementTap;

  @override
  Widget build(BuildContext context) {
    final track = controller.selected;
    if (track == null) {
      return const SizedBox(
        width: 360,
        height: 480,
        child: Center(
          child: Text('先导入或搜索一首歌曲', style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    final document = controller.document!;
    return AspectRatio(
      aspectRatio: document.size.width / document.size.height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: PosterPage(
          document: document,
          page: controller.lyricPage.clamp(0, document.pages.length - 1),
          onElementTap: onElementTap,
          onBackgroundScaleStart: controller.beginBackgroundGesture,
          onBackgroundScaleUpdate: (details) => controller
              .updateBackgroundGesture(details.focalPointDelta, details.scale),
          onStickerScaleStart: controller.beginStickerGesture,
          onStickerScaleUpdate: (index, details) =>
              controller.updateStickerGesture(
                index,
                details.focalPointDelta,
                details.scale,
              ),
        ),
      ),
    );
  }
}

Widget cover(String url, double size) => ClipRRect(
  borderRadius: BorderRadius.circular(8),
  child: url.isEmpty
      ? Container(
          width: size,
          height: size,
          color: const Color(0xFF302A45),
          child: const Icon(Icons.music_note, size: 20, color: Colors.white54),
        )
      : Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: const Color(0xFF302A45),
            child: const Icon(
              Icons.music_note,
              size: 20,
              color: Colors.white54,
            ),
          ),
        ),
);
