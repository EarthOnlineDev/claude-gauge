#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

// 把系统 SF Symbol 本体渲染成 PNG：默认水平彩虹遮罩；给第5参(RRGGBB)则填纯色(黑=模板)。
// 逻辑尺寸 W×H 点，内部按 2x 像素渲染并写 144 DPI（retina 清晰）；背景强制透明（无边框）。
// 用法: sfgen <symbolName> <Wpt> <Hpt> <outPath> [RRGGBB]
int main(int argc, const char** argv) {
  @autoreleasepool {
    NSString* name = argc>1 ? [NSString stringWithUTF8String:argv[1]] : @"gauge.with.needle";
    int LW = argc>2 ? atoi(argv[2]) : 22;       // 逻辑点
    int LH = argc>3 ? atoi(argv[3]) : 21;
    NSString* outPath = argc>4 ? [NSString stringWithUTF8String:argv[4]] : @"/tmp/sf-out.png";
    const char* solidHex = argc>5 ? argv[5] : NULL;
    const int SCALE = 2;
    int W = LW*SCALE, H = LH*SCALE;             // 物理像素

    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:H weight:NSFontWeightRegular];
    NSImage* img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (!img) { fprintf(stderr, "no symbol: %s\n", [name UTF8String]); return 1; }
    img = [img imageWithSymbolConfiguration:cfg];
    NSRect pr = NSMakeRect(0, 0, img.size.width, img.size.height);
    CGImageRef sym = [img CGImageForProposedRect:&pr context:nil hints:nil];
    if (!sym) { fprintf(stderr, "no cgimage\n"); return 1; }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGContextClearRect(ctx, CGRectMake(0, 0, W, H));        // ★ 透明背景，去除残留方框
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);

    CGFloat iw = CGImageGetWidth(sym), ih = CGImageGetHeight(sym);
    CGFloat scl = fmin((CGFloat)W/iw, (CGFloat)H/ih) * 0.90;   // 留透明边距，避免贴边
    CGFloat dw = iw*scl, dh = ih*scl;
    CGRect rect = CGRectMake((W-dw)/2, (H-dh)/2, dw, dh);

    if (solidHex) {
      unsigned int r=0,g=0,b=0; sscanf(solidHex, "%02x%02x%02x", &r,&g,&b);
      CGContextSaveGState(ctx); CGContextClipToRect(ctx, rect);
      CGContextSetRGBFillColor(ctx, r/255.0, g/255.0, b/255.0, 1.0);
      CGContextFillRect(ctx, rect); CGContextRestoreGState(ctx);
    } else {
      CGFloat comps[] = {
        0xe0/255.0,0x48/255.0,0x3d/255.0,1, 0xe0/255.0,0x8a/255.0,0x2b/255.0,1,
        0xe8/255.0,0xc9/255.0,0x4a/255.0,1, 0x1d/255.0,0x9e/255.0,0x75/255.0,1,
        0x37/255.0,0x8a/255.0,0xdd/255.0,1, 0x7f/255.0,0x77/255.0,0xdd/255.0,1 };
      CGFloat locs[] = {0,0.2,0.4,0.6,0.8,1.0};
      CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 6);
      CGContextSaveGState(ctx); CGContextClipToRect(ctx, rect);
      CGContextDrawLinearGradient(ctx, grad, CGPointMake(CGRectGetMinX(rect),0), CGPointMake(CGRectGetMaxX(rect),0),
                                  kCGGradientDrawsBeforeStartLocation|kCGGradientDrawsAfterEndLocation);
      CGContextRestoreGState(ctx); CGGradientRelease(grad);
    }
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    CGContextDrawImage(ctx, rect, sym);

    CGImageRef out = CGBitmapContextCreateImage(ctx);
    NSDictionary* props = @{ (id)kCGImagePropertyDPIWidth:  @(72*SCALE),
                             (id)kCGImagePropertyDPIHeight: @(72*SCALE) };   // ★ 144 DPI → @2x
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:outPath], CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(dst, out, (__bridge CFDictionaryRef)props);
    CGImageDestinationFinalize(dst);
    fprintf(stderr, "ok %s logical %dx%d @2x=%dx%dpx -> %s\n", [name UTF8String], LW, LH, W, H, [outPath UTF8String]);
  }
  return 0;
}
