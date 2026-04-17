#import <Foundation/Foundation.h>

#import "TagLibMetadataExtractor.h"

static NSString *NonNil(NSString * _Nullable value)
{
    return value ?: @"<nil>";
}

static void PrintMetadata(NSString *label, TagLibAudioMetadata *metadata)
{
    printf("[%s] %s\n", label.UTF8String, NonNil(metadata.title).UTF8String);
    printf("  title=%s\n", NonNil(metadata.title).UTF8String);
    printf("  artist=%s\n", NonNil(metadata.artist).UTF8String);
    printf("  album=%s\n", NonNil(metadata.album).UTF8String);
    printf("  genre=%s\n", NonNil(metadata.genre).UTF8String);
    printf("  comment=%s\n", NonNil(metadata.comment).UTF8String);
    printf("  year=%s\n", NonNil(metadata.year).UTF8String);
    printf("  releaseDate=%s\n", NonNil(metadata.releaseDate).UTF8String);
    printf("  track=%ld totalTracks=%ld trackText=%s\n",
           (long)metadata.trackNumber,
           (long)metadata.totalTracks,
           NonNil(metadata.trackNumberText).UTF8String);
    printf("  disc=%ld totalDiscs=%ld discText=%s\n",
           (long)metadata.discNumber,
           (long)metadata.totalDiscs,
           NonNil(metadata.discNumberText).UTF8String);
    printf("  duration=%.1f bitrate=%ld sampleRate=%ld channels=%ld codec=%s\n",
           metadata.duration,
           (long)metadata.bitrate,
           (long)metadata.sampleRate,
           (long)metadata.channels,
           NonNil(metadata.codec).UTF8String);
}

static void PrintRawMetadata(NSDictionary<NSString *, NSObject *> *rawMetadata)
{
    NSArray<NSDictionary<NSString *, NSObject *> *> *properties =
        (NSArray<NSDictionary<NSString *, NSObject *> *> *)rawMetadata[@"properties"];
    printf("[raw-properties]\n");
    for (NSDictionary<NSString *, NSObject *> *entry in properties) {
        NSString *key = (NSString *)(entry[@"key"] ?: @"");
        NSString *value = (NSString *)(entry[@"value"] ?: @"");
        printf("  %s=%s\n", key.UTF8String, value.UTF8String);
    }

    NSArray<NSDictionary<NSString *, NSObject *> *> *frames =
        (NSArray<NSDictionary<NSString *, NSObject *> *> *)rawMetadata[@"id3v2Frames"];
    if (frames.count > 0) {
        printf("[raw-id3v2-frames]\n");
        for (NSDictionary<NSString *, NSObject *> *entry in frames) {
            NSString *frameID = (NSString *)(entry[@"id"] ?: @"");
            NSString *value = (NSString *)(entry[@"value"] ?: @"");
            NSString *description = (NSString *)(entry[@"description"] ?: @"");
            if (description.length > 0) {
                printf("  %s (%s)=%s\n",
                       frameID.UTF8String,
                       description.UTF8String,
                       value.UTF8String);
            } else {
                printf("  %s=%s\n", frameID.UTF8String, value.UTF8String);
            }
        }
    }
}

static NSURL *FileURLFromArgument(const char *argument)
{
    NSString *path = [[NSString stringWithUTF8String:argument] stringByStandardizingPath];
    if (![path isAbsolutePath]) {
        path = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:path];
    }

    return [NSURL fileURLWithPath:path];
}

static int ReadCommand(int argc, const char *argv[])
{
    for (int index = 2; index < argc; index++) {
        NSURL *fileURL = FileURLFromArgument(argv[index]);
        NSError *error = nil;
        TagLibAudioMetadata *metadata = [TagLibMetadataExtractor extractMetadataFromURL:fileURL error:&error];
        printf("[read] %s\n", fileURL.lastPathComponent.UTF8String);
        if (!metadata) {
            printf("  error=%s\n", NonNil(error.localizedDescription).UTF8String);
            continue;
        }

        PrintMetadata(@"metadata", metadata);
    }

    return 0;
}

static int RawCommand(int argc, const char *argv[])
{
    for (int index = 2; index < argc; index++) {
        NSURL *fileURL = FileURLFromArgument(argv[index]);
        NSError *error = nil;
        NSDictionary<NSString *, NSObject *> *rawMetadata = [TagLibMetadataExtractor rawMetadataForURL:fileURL error:&error];
        printf("[raw] %s\n", fileURL.lastPathComponent.UTF8String);
        if (!rawMetadata) {
            printf("  error=%s\n", NonNil(error.localizedDescription).UTF8String);
            continue;
        }

        PrintRawMetadata(rawMetadata);
    }

    return 0;
}

static int WriteTrackCommand(int argc, const char *argv[])
{
    if (argc < 4 || argc > 5) {
        fprintf(stderr, "usage: TagLibBridgeSmoke write-track <file> <trackText> [discText|-]\n");
        return 64;
    }

    NSURL *fileURL = FileURLFromArgument(argv[2]);
    NSString *trackText = [NSString stringWithUTF8String:argv[3]];
    NSString *discText = nil;
    if (argc == 5) {
        NSString *rawDiscText = [NSString stringWithUTF8String:argv[4]];
        if (![rawDiscText isEqualToString:@"-"]) {
            discText = rawDiscText;
        }
    }

    NSError *error = nil;
    BOOL didWrite = [TagLibMetadataExtractor writeTrackNumberText:trackText
                                                   discNumberText:discText
                                                            toURL:fileURL
                                                            error:&error];
    if (!didWrite) {
        fprintf(stderr, "write-track failed: %s\n", NonNil(error.localizedDescription).UTF8String);
        return 1;
    }

    TagLibAudioMetadata *metadata = [TagLibMetadataExtractor extractMetadataFromURL:fileURL error:&error];
    if (!metadata) {
        fprintf(stderr, "post-write read failed: %s\n", NonNil(error.localizedDescription).UTF8String);
        return 1;
    }

    PrintMetadata(@"after-write-track", metadata);
    return 0;
}

static int WriteRoundtripCommand(int argc, const char *argv[])
{
    if (argc != 3) {
        fprintf(stderr, "usage: TagLibBridgeSmoke write-roundtrip <file>\n");
        return 64;
    }

    NSURL *fileURL = FileURLFromArgument(argv[2]);
    NSError *error = nil;
    TagLibAudioMetadata *before = [TagLibMetadataExtractor extractMetadataFromURL:fileURL error:&error];
    if (!before) {
        fprintf(stderr, "pre-write read failed: %s\n", NonNil(error.localizedDescription).UTF8String);
        return 1;
    }

    TagLibAudioMetadata *updated = [[TagLibAudioMetadata alloc] init];
    updated.title = @"Smoke Title";
    updated.artist = @"Smoke Artist";
    updated.album = @"Smoke Album";
    updated.albumArtist = @"Smoke Album Artist";
    updated.composer = @"Smoke Composer";
    updated.genre = @"Smoke Genre";
    updated.comment = @"Smoke Comment";
    updated.year = @"2026";
    updated.releaseDate = @"2026-03-18";
    updated.trackNumber = 0;
    updated.totalTracks = 0;
    updated.discNumber = 0;
    updated.totalDiscs = 0;
    updated.explicitContent = YES;

    if (![TagLibMetadataExtractor writeMetadata:updated toURL:fileURL error:&error]) {
        fprintf(stderr, "writeMetadata failed: %s\n", NonNil(error.localizedDescription).UTF8String);
        return 1;
    }

    if (![TagLibMetadataExtractor writeTrackNumberText:@"02/09"
                                        discNumberText:@"1/1"
                                                 toURL:fileURL
                                                 error:&error]) {
        fprintf(stderr, "writeTrackNumberText failed: %s\n", NonNil(error.localizedDescription).UTF8String);
        return 1;
    }

    TagLibAudioMetadata *after = [TagLibMetadataExtractor extractMetadataFromURL:fileURL error:&error];
    if (!after) {
        fprintf(stderr, "post-write read failed: %s\n", NonNil(error.localizedDescription).UTF8String);
        return 1;
    }

    PrintMetadata(@"before", before);
    PrintMetadata(@"after", after);
    return 0;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr,
                    "usage: TagLibBridgeSmoke read <files...>\n"
                    "   or: TagLibBridgeSmoke raw <files...>\n"
                    "   or: TagLibBridgeSmoke write-track <file> <trackText> [discText|-]\n"
                    "   or: TagLibBridgeSmoke write-roundtrip <file>\n");
            return 64;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"read"]) {
            return ReadCommand(argc, argv);
        }
        if ([command isEqualToString:@"raw"]) {
            return RawCommand(argc, argv);
        }
        if ([command isEqualToString:@"write-track"]) {
            return WriteTrackCommand(argc, argv);
        }
        if ([command isEqualToString:@"write-roundtrip"]) {
            return WriteRoundtripCommand(argc, argv);
        }

        fprintf(stderr, "unknown command: %s\n", argv[1]);
        return 64;
    }
}
