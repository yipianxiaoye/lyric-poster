import 'dart:convert';

import 'package:http/http.dart' as http;

/// Public GitHub profile fields only. These defaults were checked against the
/// GitHub users API; they keep the About page usable without internet access.
class GitHubProfile {
  const GitHubProfile({
    required this.login,
    required this.id,
    required this.profileUrl,
    this.avatarUrl = '',
    this.name,
    this.bio,
    this.location,
  });

  static const author = GitHubProfile(
    login: 'yipianxiaoye',
    id: 123964995,
    profileUrl: 'https://github.com/yipianxiaoye',
    avatarUrl: 'https://avatars.githubusercontent.com/u/123964995?v=4',
  );

  final String login, profileUrl, avatarUrl;
  final int id;
  final String? name, bio, location;

  String get displayName => name?.trim().isNotEmpty == true ? name! : login;

  factory GitHubProfile.fromMap(Map<String, dynamic> data) => GitHubProfile(
    login: data['login'] as String,
    id: (data['id'] as num).toInt(),
    profileUrl: data['html_url'] as String,
    avatarUrl: data['avatar_url'] as String? ?? '',
    name: data['name'] as String?,
    bio: data['bio'] as String?,
    location: data['location'] as String?,
  );
}

Future<GitHubProfile> loadAuthorProfile({http.Client? client}) async {
  final api = client ?? http.Client();
  try {
    final response = await api
        .get(
          Uri.https('api.github.com', '/users/yipianxiaoye'),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'LyricPoster/1.5.1',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return GitHubProfile.author;
    final profile = GitHubProfile.fromMap(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
    // Follow only the verified author's numeric identity.
    return profile.id == GitHubProfile.author.id
        ? profile
        : GitHubProfile.author;
  } catch (_) {
    return GitHubProfile.author;
  } finally {
    if (client == null) api.close();
  }
}
