import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

const directOutbound = 'DIRECT';
const routedOutbound = '';

/// Built-in targets match checker names registered in core/service_check.go.
@immutable
sealed class ServiceTarget {
  const ServiceTarget();

  String get id;
  String get label;
  String? get icon;
  String? get customUrl => null;

  static const google = BuiltinServiceTarget('google', 'Google', 'google');
  static const github = BuiltinServiceTarget('github', 'GitHub', 'github');
  static const youtube = BuiltinServiceTarget('youtube', 'YouTube', 'youtube');
  static const chatgpt = BuiltinServiceTarget('chatgpt', 'ChatGPT', 'openai');
  static const claude = BuiltinServiceTarget('claude', 'Claude', 'claude');
  static const gemini = BuiltinServiceTarget('gemini', 'Gemini', 'gemini');
  static const netflix = BuiltinServiceTarget('netflix', 'Netflix', 'netflix');
  static const disneyPlus = BuiltinServiceTarget(
    'disney-plus',
    'Disney+',
    'disneyplus',
  );
  static const primeVideo = BuiltinServiceTarget(
    'prime-video',
    'Prime Video',
    'primevideo',
  );
  static const spotify = BuiltinServiceTarget('spotify', 'Spotify', 'spotify');
  static const tiktok = BuiltinServiceTarget('tiktok', 'TikTok', 'tiktok');
  static const discord = BuiltinServiceTarget('discord', 'Discord', 'discord');
  static const bilibili = BuiltinServiceTarget(
    'bilibili',
    'Bilibili',
    'bilibili',
  );

  static const List<BuiltinServiceTarget> values = [
    google,
    github,
    youtube,
    chatgpt,
    claude,
    gemini,
    netflix,
    disneyPlus,
    primeVideo,
    spotify,
    tiktok,
    discord,
    bilibili,
  ];

  static BuiltinServiceTarget? byId(String id) {
    for (final target in values) {
      if (target.id == id) return target;
    }
    return null;
  }
}

final class BuiltinServiceTarget extends ServiceTarget {
  const BuiltinServiceTarget(this.id, this.label, this.icon);

  @override
  final String id;

  @override
  final String label;

  @override
  final String icon;
}

final class CustomServiceTarget extends ServiceTarget {
  const CustomServiceTarget({
    required this.id,
    required this.label,
    required String url,
  }) : customUrl = url;

  @override
  final String id;

  @override
  final String label;

  @override
  final String customUrl;

  @override
  String? get icon => null;

  @override
  bool operator ==(Object other) =>
      other is CustomServiceTarget &&
      other.id == id &&
      other.label == label &&
      other.customUrl == customUrl;

  @override
  int get hashCode => Object.hash(id, label, customUrl);
}

String customServiceLabel(String label, String url) {
  final trimmed = label.trim();
  if (trimmed.isNotEmpty) return trimmed;
  final host = Uri.tryParse(url.trim())?.host ?? '';
  return host.isNotEmpty ? host : url.trim();
}

enum ServiceProbeStatus {
  available('available'),
  unavailable('unavailable'),
  restricted('restricted'),
  disallowedIsp('disallowed-isp'),
  blocked('blocked'),
  unsupportedRegion('unsupported-region'),
  originalsOnly('originals-only'),
  comingSoon('coming-soon'),
  timeout('timeout'),
  failed('failed');

  const ServiceProbeStatus(this.id);

  final String id;

  static ServiceProbeStatus byId(String id) {
    for (final status in values) {
      if (status.id == id) return status;
    }
    return ServiceProbeStatus.failed;
  }
}

List<ServiceTarget> orderServiceTargets(
  List<String> order, {
  List<CustomService> customServices = const [],
}) {
  final customById = <String, CustomServiceTarget>{
    for (final item in customServices)
      if (item.id.isNotEmpty && item.url.isNotEmpty)
        item.id: CustomServiceTarget(
          id: item.id,
          label: customServiceLabel(item.label, item.url),
          url: item.url,
        ),
  };
  ServiceTarget? resolve(String id) => ServiceTarget.byId(id) ?? customById[id];
  return {
    for (final id in order) ?resolve(id),
    ...ServiceTarget.values,
    ...customById.values,
  }.toList();
}

class ServiceCheck {
  const ServiceCheck(
    this.status, {
    this.delay,
    this.chains = const [],
    this.region,
    this.checkedAt,
    this.coreEpoch = 0,
    this.routeVersion = 0,
    this.hits = const [],
  });

  factory ServiceCheck.of(ServiceCheckItem item) {
    return ServiceCheck(
      ServiceProbeStatus.byId(item.status),
      delay: item.delay > 0 ? item.delay : null,
      chains: item.chains,
      region: item.region.isEmpty ? null : item.region,
      checkedAt: item.checkedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(item.checkedAt)
          : null,
      coreEpoch: item.coreEpoch,
      routeVersion: item.routeVersion,
      hits: item.hits,
    );
  }

  final ServiceProbeStatus status;
  final int? delay;
  final List<String> chains;
  final String? region;
  final DateTime? checkedAt;
  final int coreEpoch;
  final int routeVersion;
  final List<RouteHit> hits;

  String? get node => chains.firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is ServiceCheck &&
      other.status == status &&
      other.delay == delay &&
      listEquals(other.chains, chains) &&
      other.region == region &&
      other.checkedAt == checkedAt &&
      other.coreEpoch == coreEpoch &&
      other.routeVersion == routeVersion &&
      listEquals(other.hits, hits);

  @override
  int get hashCode => Object.hash(
    status,
    delay,
    Object.hashAll(chains),
    region,
    checkedAt,
    coreEpoch,
    routeVersion,
    Object.hashAll(hits),
  );

  @override
  String toString() =>
      'ServiceCheck(${status.id}, delay: $delay, node: $node, region: $region)';
}

/// An empty [proxyName] lets the Core route by its rules; an empty [targets]
/// checks every built-in service.
Future<Map<ServiceTarget, ServiceCheck>> checkServices(
  CoreController core, {
  String proxyName = '',
  List<ServiceTarget> targets = const [],
  Duration timeout = probeTimeoutDuration,
}) async {
  final byId = {for (final target in targets) target.id: target};
  final items = await core.serviceCheck(
    ServiceCheckParams(
      proxyName: proxyName,
      names: [
        for (final target in targets)
          if (target is BuiltinServiceTarget) target.id,
      ],
      custom: [
        for (final target in targets)
          if (target case CustomServiceTarget(:final id, :final customUrl))
            CustomServiceCheck(name: id, url: customUrl),
      ],
      timeout: timeout.inMilliseconds,
    ),
  );
  return {
    for (final item in items)
      ?(byId[item.name] ?? ServiceTarget.byId(item.name)): ServiceCheck.of(
        item,
      ),
  };
}

IpInfo Function(String) _json(IpInfo Function(Map<String, dynamic>) parse) {
  return (body) => parse(jsonDecode(body) as Map<String, dynamic>);
}

final Map<String, IpInfo Function(String)> ipInfoSources = {
  'https://www.cloudflare.com/cdn-cgi/trace': IpInfo.fromCloudflareTrace,
  'https://api.ip.sb/geoip': _json(IpInfo.fromIpSbJson),
  'https://ipinfo.io/json': _json(IpInfo.fromIpInfoIoJson),
  'https://ipwho.is': _json(IpInfo.fromIpWhoIsJson),
  'https://get.geojs.io/v1/ip/geo.json': _json(IpInfo.fromGeoJsJson),
  'https://api.country.is': _json(IpInfo.fromCountryIsJson),
  'https://api.ipquery.io/?format=json': _json(IpInfo.fromIpQueryJson),
  'https://ident.me/json': _json(IpInfo.fromIdentMeJson),
};

/// Raw so the route stamp survives; [parseOutboundIp] reads the address.
Future<OutboundIpResult> lookupOutboundIp(
  CoreController core,
  String proxyName, {
  Duration timeout = outboundIpTimeoutDuration,
}) {
  return core.outboundIp(
    OutboundIpParams(
      proxyName: proxyName,
      urls: ipInfoSources.keys.toList(),
      timeout: timeout.inMilliseconds,
    ),
  );
}

IpInfo? parseOutboundIp(OutboundIpResult result) {
  if (result.error != null || result.body.isEmpty) {
    return null;
  }
  final parse = ipInfoSources[result.url];
  if (parse == null) return null;
  try {
    return parse(result.body);
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}
