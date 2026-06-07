/*
<samplecode>
  <abstract>
  Loads PNG sprite assets from the application bundle into `MTL::Texture`
  instances using `CGImage` and `MTKTextureLoader`.
  </abstract>
</samplecode>
*/

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
//
// Copyright 2026 Apple Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#include "TextureLoader.h"
#import <MetalKit/MetalKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

MTL::Texture* newTextureFromFile(const std::string& texturePath, MTL::Device* pDevice)
{
    NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:texturePath.c_str()]];
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:(__bridge id<MTLDevice>)pDevice];
    
    NSError* __autoreleasing error = nil;
    id<MTLTexture> texture = [loader newTextureWithContentsOfURL:url
                                                         options:@{MTKTextureLoaderOptionLoadAsArray : @(YES), /* Shader converter pipelines expect texture arrays */
                                                                   MTKTextureLoaderOptionTextureStorageMode : @(MTLStorageModePrivate),
                                                                   MTKTextureLoaderOptionTextureUsage : @(MTLTextureUsageShaderRead),
                                                                   MTKTextureLoaderOptionGenerateMipmaps : @(YES)}
                                                           error:&error];
    
    if (!texture)
    {
        NSLog(@"Error loading texture at \"%s\": %@", texturePath.c_str(), error.localizedDescription);
    }
    assert(texture);
    
    return (__bridge_retained MTL::Texture *)texture; // transfer ownership to metal-cpp
}

MTL::Texture* newTextureArrayFromFiles(const std::vector<std::string>& texturePaths, MTL::Device* pDevice, MTL::CommandBuffer* pCommandBuffer)
{
    // Load textures:
    std::vector<NS::SharedPtr<MTL::Texture>> textures;
    for (size_t i = 0; i < texturePaths.size(); ++i)
    {
        textures.push_back(NS::TransferPtr(newTextureFromFile(texturePaths[i], pDevice)));
    }
    
    MTL::Texture* pTexture = nullptr;
    
    // Combine textures into a single texture array:
    
    if (textures.size() > 0)
    {
        auto pTextureDesc = NS::TransferPtr(MTL::TextureDescriptor::alloc()->init());
        
        pTextureDesc->setWidth(textures[0]->width());
        pTextureDesc->setHeight(textures[0]->height());
        pTextureDesc->setPixelFormat(textures[0]->pixelFormat());
        
        pTextureDesc->setTextureType(MTL::TextureType2DArray);
        pTextureDesc->setUsage(MTL::TextureUsageShaderRead);
        pTextureDesc->setStorageMode(MTL::StorageModePrivate);
        pTextureDesc->setArrayLength(textures.size());
        pTextureDesc->setMipmapLevelCount(std::log2(textures[0]->width()));
        
        pTexture = pDevice->newTexture(pTextureDesc.get());
        
        // Use Metal to efficiently blit textures into the texture array:
        
        auto pAutoreleasePool = NS::TransferPtr(NS::AutoreleasePool::alloc()->init());
        
        MTL::CommandBuffer* pCmd       = pCommandBuffer;
        MTL::BlitCommandEncoder* pBlit = pCmd->blitCommandEncoder();
        
        for (size_t i = 0; i < textures.size(); ++i)
        {
            
            auto w = textures[i]->width();
            auto h = textures[i]->height();
            auto d = textures[i]->depth();
            
            pBlit->copyFromTexture(textures[i].get(), 0, 0, MTL::Origin(0,0,0), MTL::Size(w,h,d),
                                   pTexture, i, 0, MTL::Origin(0,0,0));
            
        }
        
        pBlit->generateMipmaps(pTexture);
        
        pBlit->endEncoding();
    }

    return pTexture;
}

CGRect calculateReferenceBounds(char c, CTFontRef font, CGColorRef color, CGContextRef ctx)
{
    NSString* str = [NSString stringWithFormat:@"%c", c];
    NSMutableAttributedString* attributedString = [[NSMutableAttributedString alloc] initWithString:str];
    [attributedString addAttribute:NSFontAttributeName value:(__bridge id)font range:NSMakeRange(0,1)];
    [attributedString addAttribute:NSForegroundColorAttributeName value:(__bridge id)color range:NSMakeRange(0,1)];
    
    CTLineRef lineOfText = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributedString);
    
    CGContextSetTextPosition(ctx, 0, 0);
    CGRect rect = CTLineGetImageBounds(lineOfText, ctx);
    
    CFRelease(lineOfText);
    return rect;
}

FontAtlas newFontAtlas(MTL::Device* pDevice)
{
    FontAtlas fontAtlas;
    
    // Render font atlas into a Core Graphics context:
    
    const uint32_t bitmapW = 1024;
    const uint32_t bitmapH = 1024;
    const uint32_t bitmapChannels = 4;
    const uint32_t bitmapSize = bitmapW * bitmapH * bitmapChannels;
    const uint32_t bitsPerComponent = 8;
    const uint32_t bytesPerRow = bitmapW * bitmapChannels;
    
    uint8_t* bitmap = new uint8_t[bitmapSize];
    memset(bitmap, 0x0, bitmapSize);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(bitmap,
                                             bitmapW,
                                             bitmapH,
                                             bitsPerComponent,
                                             bytesPerRow,
                                             colorSpace,
                                             kCGImageAlphaPremultipliedLast);
    assert(ctx);
    
    CGFloat margin       = (CGFloat)bitmapW * 0.120/2.0;
    CGColorRef color     = CGColorCreateGenericRGB(1.0, 0.0, 0.0, 1.0);
    CGFloat fontSize     = (CGFloat)bitmapW * 0.08; // Each character takes 8% of the bitmap
    CFStringRef fontName = CFSTR("PT Mono");
    
    CTFontRef font = CTFontCreateWithName(fontName, fontSize, nullptr);
    
    CGFloat x = margin;
    CGFloat y = margin;
    
    CGRect minBounds = calculateReferenceBounds('X', font, color, ctx);
    
    std::vector<CGColorRef> colors = {
        CGColorCreateGenericRGB(99/255.0, 180/255.0, 73/255.0, 1.0),
        CGColorCreateGenericRGB(255/255.0, 179/255.0, 36/255.0, 1.0),
        CGColorCreateGenericRGB(250/255.0, 131/255.0, 28/255.0, 1.0),
        CGColorCreateGenericRGB(226/255.0, 67/255.0, 59/255.0, 1.0),
        CGColorCreateGenericRGB(149/255.0, 72/255.0, 150/255.0, 1.0),
        CGColorCreateGenericRGB(7/255.0, 160/255.0, 222/255.0, 1.0)
    };
    
    for (int i = 0; i < sizeof(g_chars)/sizeof(g_chars[0]); ++i )
    {
        NSString* str = [NSString stringWithFormat:@"%c", g_chars[i]];
        NSMutableAttributedString* attributedString = [[NSMutableAttributedString alloc] initWithString:str];
        [attributedString addAttribute:NSFontAttributeName value:(__bridge id)font range:NSMakeRange(0,1)];
        
        CGColorRef charColor = colors[rand() % colors.size()];
        [attributedString addAttribute:NSForegroundColorAttributeName value:(__bridge id)charColor range:NSMakeRange(0,1)];
        
        CTLineRef lineOfText = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributedString);
        
        CGContextSetTextPosition(ctx, 0, 0);
        CGRect rect = CTLineGetImageBounds(lineOfText, ctx);
        
        // ImageBounds closely wraps the glyphs. To make the font behave
        // as a monospaced one, normalize the bounds to the reference one
        // and center the glyph:
        CGSize oldSize = rect.size;
        rect.size.width = std::max(rect.size.width, minBounds.size.width);
        rect.size.height = std::max(rect.size.height, minBounds.size.height);
        
        CGFloat dx = (rect.size.width - oldSize.width) * 0.5;
        CGFloat dy = (rect.size.height - oldSize.height) * 0.5;
        
        // Note: this adjustment centers all rendered glyphs into the sprite.
        // A realistic font would be character-dependent where, for example,
        // the UI renders the "." character is aligned to the bottom-left
        // marging.
        rect.origin.x -= dx;
        rect.origin.y -= dy;
    
#define DEBUG_CHAR_BOUNDS 0
#if DEBUG_CHAR_BOUNDS
        CGContextSetStrokeColorWithColor(ctx, color);
        
        CGRect boundsRect = CGRectMake(x+rect.origin.x,
                                       y+rect.origin.y,
                                       rect.size.width,
                                       rect.size.height);
        
        CGContextAddRect(ctx, boundsRect);
        CGContextDrawPath(ctx, kCGPathStroke);
#endif // DEBUG_CHAR_BOUNDS
        
        CGContextSetTextPosition(ctx, x, y);
        CTLineDraw(lineOfText, ctx);
        
        // Calculate and store UVs
        
        FontAtlas::CharUVs& uvs = fontAtlas.charToUVs[g_chars[i] - g_chars[0]];
        uvs.sw = simd_make_float2((x+rect.origin.x) / bitmapW,
                                  (-(y+rect.origin.y)+bitmapH) / bitmapH);
        
        uvs.se = simd_make_float2((x+rect.origin.x+rect.size.width) / bitmapW,
                                  (-(y+rect.origin.y)+bitmapH) / bitmapH);
        
        uvs.ne = simd_make_float2((x+rect.origin.x+rect.size.width) / bitmapW,
                                  (-(y+rect.origin.y+rect.size.height)+bitmapH) / bitmapH);
        
        uvs.nw = simd_make_float2((x+rect.origin.x) / bitmapW,
                                  (-(y+rect.origin.y+rect.size.height)+bitmapH) / bitmapH);

        // Calculate next character location in atlas:
        
        x += rect.size.width + margin;
        if ((x + rect.size.width + margin/2) >= (CGFloat)bitmapW)
        {
            x = margin;
            y += rect.size.height + margin;
        }
        
        CFRelease(lineOfText);
    }
    
    for (CGColorRef color : colors)
    {
        CFRelease(color);
    }
    
    // Create a Metal texture with the font atlas
    
    auto pTextureDesc = NS::TransferPtr(MTL::TextureDescriptor::alloc()->init());
    pTextureDesc->setWidth(bitmapW);
    pTextureDesc->setHeight(bitmapH);
    pTextureDesc->setTextureType(MTL::TextureType2DArray);
    pTextureDesc->setUsage(MTL::TextureUsageShaderRead);
    pTextureDesc->setArrayLength(1);
    pTextureDesc->setStorageMode(MTL::StorageModeShared);
    pTextureDesc->setMipmapLevelCount(1);
    
    fontAtlas.texture = NS::TransferPtr(pDevice->newTexture(pTextureDesc.get()));
    fontAtlas.texture->setLabel(MTLSTR("Font Atlas Texture"));
    fontAtlas.texture->replaceRegion(MTL::Region(0, 0, bitmapW, bitmapH), 0, 0,
                                       bitmap, bytesPerRow, bitmapW * bitmapH * bitmapChannels);
    
    // Release Core Graphics and Core Text objects
    CFRelease(color);
    CFRelease(font);
    CFRelease(ctx);
    CFRelease(colorSpace);
    delete [] bitmap;
    
    return fontAtlas;
}
