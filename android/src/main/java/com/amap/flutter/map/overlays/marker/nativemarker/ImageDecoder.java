package com.amap.flutter.map.overlays.marker.nativemarker;

/** 在后台线程解码资源；失败抛异常，消息进入 imageDecodeFailed 错误 */
public interface ImageDecoder {
    DecodedImage decode(ImageSource source) throws Exception;
}
