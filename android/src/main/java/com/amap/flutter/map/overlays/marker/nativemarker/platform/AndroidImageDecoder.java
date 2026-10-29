package com.amap.flutter.map.overlays.marker.nativemarker.platform;

import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import com.amap.flutter.map.overlays.marker.nativemarker.DecodedImage;
import com.amap.flutter.map.overlays.marker.nativemarker.ImageDecoder;
import com.amap.flutter.map.overlays.marker.nativemarker.ImageSource;

import java.io.InputStream;

/** 后台线程解码 bytes / asset；不做密度缩放，像素尺寸即图片原始像素 */
public final class AndroidImageDecoder implements ImageDecoder {
    /** asset 逻辑名 → 打包路径，由宿主提供（FlutterLoader） */
    public interface AssetResolver {
        String lookup(String asset, String assetPackage);
    }

    private final AssetManager assets;
    private final AssetResolver resolver;

    public AndroidImageDecoder(AssetManager assets, AssetResolver resolver) {
        this.assets = assets;
        this.resolver = resolver;
    }

    @Override
    public DecodedImage decode(ImageSource source) throws Exception {
        BitmapFactory.Options opts = new BitmapFactory.Options();
        opts.inScaled = false;
        Bitmap bitmap;
        if (ImageSource.TYPE_BYTES.equals(source.type)) {
            bitmap = BitmapFactory.decodeByteArray(source.data, 0, source.data.length, opts);
        } else {
            try (InputStream in = assets.open(resolver.lookup(source.asset, source.assetPackage))) {
                bitmap = BitmapFactory.decodeStream(in, null, opts);
            }
        }
        if (bitmap == null) {
            throw new IllegalArgumentException("无法解码图片: " + source.id);
        }
        return new BitmapImage(bitmap);
    }
}
