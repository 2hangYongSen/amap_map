import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

/// 图片资源来源
enum MarkerImageSourceType {
  /// Flutter asset
  asset,

  /// PNG/JPEG 字节
  bytes,
}

/// 原生点位使用的图片资源。
///
/// 字节资源在构造时复制并计算摘要，调用方应缓存资源对象，
/// 不要在每次 build 时重新调用 [MarkerImageResource.bytes]。
@immutable
final class MarkerImageResource {
  /// Flutter asset 来源；[id] 由调用方指定，要求全局稳定。
  const MarkerImageResource.asset({
    required this.id,
    required String this.assetName,
    this.package,
    this.pixelRatio = 1,
  })  : type = MarkerImageSourceType.asset,
        _bytes = null;

  /// PNG/JPEG 字节来源；构造时复制字节并计算摘要，id 自动生成。
  ///
  /// id 为 `b:<sha256 前 32 位十六进制>@<pixelRatio>`，内容或像素比变化都会得到新 id。
  factory MarkerImageResource.bytes(
    Uint8List bytes, {
    double pixelRatio = 1,
  }) {
    // 先复制，之后只读私有副本，调用方再改原数组也不受影响
    final Uint8List copy = Uint8List.fromList(bytes);
    debugDigestComputeCount++;
    final String digest = sha256.convert(copy).toString().substring(0, 32);
    return MarkerImageResource._(
      id: 'b:$digest@$pixelRatio',
      pixelRatio: pixelRatio,
      bytes: copy,
    );
  }

  const MarkerImageResource._({
    required this.id,
    required this.pixelRatio,
    required Uint8List bytes,
  })  : type = MarkerImageSourceType.bytes,
        assetName = null,
        package = null,
        _bytes = bytes;

  /// 摘要计算次数，仅供测试断言“只在构造时计算”
  @visibleForTesting
  static int debugDigestComputeCount = 0;

  /// 资源 id
  final String id;

  /// 来源类型
  final MarkerImageSourceType type;

  /// 图片像素比
  final double pixelRatio;

  /// asset 名称，仅 [MarkerImageSourceType.asset] 有值
  final String? assetName;

  /// asset 所在 package
  final String? package;

  // 私有副本，不提供公共 getter
  final Uint8List? _bytes;

  /// 序列化为通道载荷，内部使用。字节只读传给编解码器，请勿修改返回的数据。
  Map<String, dynamic> toMap() {
    if (type == MarkerImageSourceType.bytes) {
      return <String, dynamic>{
        'id': id,
        'type': 'bytes',
        'data': _bytes,
        'pixelRatio': pixelRatio,
      };
    }
    return <String, dynamic>{
      'id': id,
      'type': 'asset',
      'asset': assetName,
      'package': package,
      'pixelRatio': pixelRatio,
    };
  }

  // 只比较 id 与来源类型，不比较字节
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerImageResource && id == other.id && type == other.type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() =>
      'MarkerImageResource{id: $id, type: $type, pixelRatio: $pixelRatio}';
}
