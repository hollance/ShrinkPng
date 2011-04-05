/*
	ShrinkPng - Shrinks an image to 50% by averaging the color (and alpha)
	of each 2x2 pixel block.

	You use this to shrink Retina images (@2x) down to the lower resolution.
	The assumption here is that the source image is drawn on a 2x2 grid and 
	that all line widths and so on are multiples of 2.

	The output looks similar to bicubic scaling, but slightly sharper.

	Known Bugs:

	If the image contains a color profile (as images saved from Gimp tend to)
	then the converted pixel values will be a little off. I have not found a
	way yet to load PNGs without the color profile, but you can strip these
	headers using pngcrush before running ShrinkPng:

		pngcrush -rem gAMA -rem cHRM -rem iCCP -rem sRGB in@2x.png out@2x.png
 */

#import <Foundation/Foundation.h>

CGImageRef LoadPNG(NSString* filename)
{
	CGDataProviderRef provider = CGDataProviderCreateWithFilename([filename UTF8String]);
	if (provider == NULL)
	{
		fprintf(stderr, "Could not open '%s'\n", [filename UTF8String]);
		return NULL;
	}

	CGImageRef image = CGImageCreateWithPNGDataProvider(provider, NULL, false, kCGRenderingIntentDefault);
	CGDataProviderRelease(provider);
	return image;
}

BOOL SavePNG(NSString* filename, CGImageRef image)
{
	CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
		(CFURLRef)[NSURL fileURLWithPath:filename], kUTTypePNG, 1, NULL);

	if (dest == NULL)
	{
		fprintf(stderr, "Could not create image destination\n");
		return NO;
	}

	CGImageDestinationAddImage(dest, image, NULL);
	CGImageDestinationFinalize(dest);
	CFRelease(dest);
	return YES;
}

unsigned char* CreateBytesFromImage(CGImageRef image)
{
	size_t width = CGImageGetWidth(image);
	size_t height = CGImageGetHeight(image);

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	if (colorSpace == NULL)
	{
		fprintf(stderr, "Could not create color space\n");
		return NULL;
	}

	void* contextData = calloc(width * height, 4);
	if (contextData == NULL)
	{
		fprintf(stderr, "Could not allocate memory\n");
		CGColorSpaceRelease(colorSpace);
		return NULL;
	}

	CGContextRef context = CGBitmapContextCreate(
		contextData, width, height, 8, width * 4, colorSpace,
		kCGImageAlphaPremultipliedFirst);

	CGColorSpaceRelease(colorSpace);

	if (context == NULL)
	{
		fprintf(stderr, "Could not create context\n");
		free(contextData);
		return NULL;
	}

	CGRect rect = CGRectMake(0.0f, 0.0f, width, height);
	CGContextDrawImage(context, rect, image);
	unsigned char* imageData = CGBitmapContextGetData(context);
	CGContextRelease(context);

	return imageData;
}

CGImageRef CreateImageFromBytes(unsigned char* data, size_t width, size_t height)
{
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	if (colorSpace == NULL)
	{
		fprintf(stderr, "Could not create color space\n");
		return NULL;
	}

	CGContextRef context = CGBitmapContextCreate(
		data, width, height, 8, width * 4, colorSpace,
		kCGImageAlphaPremultipliedFirst);

	CGColorSpaceRelease(colorSpace);

	if (context == NULL)
	{
		fprintf(stderr, "Could not create context\n");
		return NULL;
	}

	CGImageRef ref = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	return ref;
}

unsigned char* ShrinkBitmapData(unsigned char* inData, size_t width, size_t height)
{
	unsigned char* outData = (unsigned char*)calloc(width*height, 4);
	if (outData == NULL)
	{
		fprintf(stderr, "Could not allocate memory\n");
		return NULL;
	}

	unsigned char* ptr = outData;

	for (int y = 0; y < height; y += 2)
	{
		for (int x = 0; x < width; x += 2)
		{
			size_t offset1 = (y*width + x)*4;    // top left
			size_t offset2 = offset1 + 4;        // top right
			size_t offset3 = offset1 + width*4;  // bottom left
			size_t offset4 = offset3 + 4;        // bottom right

			int a1 = inData[offset1 + 0];
			int r1 = inData[offset1 + 1];
			int g1 = inData[offset1 + 2];
			int b1 = inData[offset1 + 3];

			int a2 = inData[offset2 + 0];
			int r2 = inData[offset2 + 1];
			int g2 = inData[offset2 + 2];
			int b2 = inData[offset2 + 3];

			int a3 = inData[offset3 + 0];
			int r3 = inData[offset3 + 1];
			int g3 = inData[offset3 + 2];
			int b3 = inData[offset3 + 3];

			int a4 = inData[offset4 + 0];
			int r4 = inData[offset4 + 1];
			int g4 = inData[offset4 + 2];
			int b4 = inData[offset4 + 3];

			// We do +2 in order to round up if the remainder is 0.5 or more.
			int r = (r1 + r2 + r3 + r4 + 2) / 4;
			int g = (g1 + g2 + g3 + g4 + 2) / 4;
			int b = (b1 + b2 + b3 + b4 + 2) / 4;
			int a = (a1 + a2 + a3 + a4 + 2) / 4;

			*ptr++ = a;
			*ptr++ = r;
			*ptr++ = g;
			*ptr++ = b;
		}
	}

	return outData;
}

int main(int argc, const char* argv[])
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	if (argc != 2)
	{
		fprintf(stderr, "Usage: ShrinkPng <input@2x.png>\n");
		return EXIT_FAILURE;
	}

	NSString* inputFilename = [NSString stringWithCString:argv[1] encoding:NSUTF8StringEncoding];
	inputFilename = [inputFilename stringByExpandingTildeInPath];

	NSString* withoutExtension = [inputFilename stringByDeletingPathExtension];
	if (![withoutExtension hasSuffix:@"@2x"])
	{
		fprintf(stderr, "Input file must be @2x\n");
		return EXIT_FAILURE;
	}

	NSString* without2x = [withoutExtension substringToIndex:withoutExtension.length - 3];
	if (without2x.length == 0)
	{
		fprintf(stderr, "Invalid input filename\n");
		return EXIT_FAILURE;
	}

	NSString* outputFilename = [without2x stringByAppendingPathExtension:@"png"];

	CGImageRef inImage = LoadPNG(inputFilename);
	if (inImage != NULL)
	{
		size_t width = CGImageGetWidth(inImage);
		size_t height = CGImageGetHeight(inImage);

		unsigned char* inData = CreateBytesFromImage(inImage);
		CGImageRelease(inImage);

		if (inData != NULL)
		{
			unsigned char* outData = ShrinkBitmapData(inData, width, height);
			free(inData);

			if (outData != NULL)
			{
				CGImageRef outImage = CreateImageFromBytes(outData, width / 2, height / 2);
				free(outData);

				if (outImage != NULL)
				{
					SavePNG(outputFilename, outImage);
					CGImageRelease(outImage);
				}
			}
		}
	}

	[pool drain];
	return 0;
}
