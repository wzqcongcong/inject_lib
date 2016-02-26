/*
 yololib
 Inject dylibs into existing Mach-O binaries
 
 
 DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
 Version 2, December 2004
 
 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
 
 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.
 
 DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
 TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
 
 0. You just DO WHAT THE FUCK YOU WANT TO.
 
 */

#include <stdio.h>
#include <string.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#import <Foundation/Foundation.h>


NSString* DYLIB_PATH;

#define DYLIB_CURRENT_VER 0x10000
#define DYLIB_COMPATIBILITY_VERSION 0x10000

#define ARMV7 9
#define ARMV6 6

unsigned long b_round(unsigned long v, unsigned long r)
{
    r--;
    v += r;
    v &= ~(long)r;
    return(v);
}

void inject_dylib(FILE* newFile, uint32_t top)
{
    fseek(newFile, top, SEEK_SET);
    struct mach_header mach;
    
    fread(&mach, sizeof(struct mach_header), 1, newFile);
    
    NSData* data = [DYLIB_PATH dataUsingEncoding:NSUTF8StringEncoding];
    
    uint32_t dylib_size = (uint32_t)[data length] + sizeof(struct dylib_command);
    dylib_size += sizeof(long) - (dylib_size % sizeof(long)); // load commands like to be aligned by long
    
    mach.ncmds += 1;
    uint32_t sizeofcmds = mach.sizeofcmds;
    mach.sizeofcmds += dylib_size;
    
    fseek(newFile, -sizeof(struct mach_header), SEEK_CUR);
    fwrite(&mach, sizeof(struct mach_header), 1, newFile);
    NSLog(@"Patching mach_header...");
    
    fseek(newFile, sizeofcmds, SEEK_CUR);
    
    struct dylib_command dyld;
    fread(&dyld, sizeof(struct dylib_command), 1, newFile);
    
    NSLog(@"Attaching dylib...");
    
    dyld.cmd = LC_LOAD_DYLIB;
    dyld.cmdsize = dylib_size;
    dyld.dylib.compatibility_version = DYLIB_COMPATIBILITY_VERSION;
    dyld.dylib.current_version = DYLIB_CURRENT_VER;
    dyld.dylib.timestamp = 2;
    dyld.dylib.name.offset = sizeof(struct dylib_command);
    fseek(newFile, -sizeof(struct dylib_command), SEEK_CUR);
    
    fwrite(&dyld, sizeof(struct dylib_command), 1, newFile);
    
    fwrite([data bytes], [data length], 1, newFile);
}

void inject_dylib_64(FILE* newFile, uint32_t top)
{
    @autoreleasepool {
        fseek(newFile, top, SEEK_SET);
        struct mach_header_64 mach;

        fread(&mach, sizeof(struct mach_header_64), 1, newFile);
        
        NSData* data = [DYLIB_PATH dataUsingEncoding:NSUTF8StringEncoding];

        unsigned long dylib_size = sizeof(struct dylib_command) + b_round(strlen([DYLIB_PATH UTF8String]) + 1, 8);

        NSLog(@"dylib size wow %lu", dylib_size);
        
        NSLog(@"mach.ncmds %u", mach.ncmds);
        
        mach.ncmds += 0x1;
        
        NSLog(@"mach.ncmds %u", mach.ncmds);
        
        uint32_t sizeofcmds = mach.sizeofcmds;
        mach.sizeofcmds += (dylib_size);
        
        fseek(newFile, -sizeof(struct mach_header_64), SEEK_CUR);
        fwrite(&mach, sizeof(struct mach_header_64), 1, newFile);
        NSLog(@"Patching mach_header...");
        
        fseek(newFile, sizeofcmds, SEEK_CUR);
        
        struct dylib_command dyld;
        fread(&dyld, sizeof(struct dylib_command), 1, newFile);
        
        NSLog(@"Attaching dylib...");
        
        dyld.cmd = LC_LOAD_DYLIB;
        dyld.cmdsize = (uint32_t) dylib_size;
        dyld.dylib.compatibility_version = DYLIB_COMPATIBILITY_VERSION;
        dyld.dylib.current_version = DYLIB_CURRENT_VER;
        dyld.dylib.timestamp = 2;
        dyld.dylib.name.offset = sizeof(struct dylib_command);
        fseek(newFile, -sizeof(struct dylib_command), SEEK_CUR);
        
        fwrite(&dyld, sizeof(struct dylib_command), 1, newFile);
        
        fwrite([data bytes], [data length], 1, newFile);
        NSLog(@"size %lu", sizeof(struct dylib_command) + [data length]);
    }
}

void inject_file(NSString* file, NSString* _dylib)
{
    char buffer[4096], binary[4096], dylib[4096];

    strlcpy(binary, [file UTF8String], sizeof(binary));
    strlcpy(dylib, [DYLIB_PATH UTF8String], sizeof(dylib));
    
    NSLog(@"dylib path: %@", DYLIB_PATH);
    FILE *binaryFile = fopen(binary, "r+");
    NSLog(@"Reading binary: %s", binary);
    fread(&buffer, sizeof(buffer), 1, binaryFile);
    
    struct fat_header* fh = (struct fat_header*) (buffer);
    
    switch (fh->magic) {
        case FAT_CIGAM:
        case FAT_MAGIC:
        {
            struct fat_arch* arch = (struct fat_arch*) &fh[1];
            NSLog(@"FAT binary!");
            int i;
            for (i = 0; i < CFSwapInt32(fh->nfat_arch); i++) {
                NSLog(@"Injecting to arch %i", CFSwapInt32(arch->cpusubtype));
                if (CFSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                    NSLog(@"64bit arch wow");
                    inject_dylib_64(binaryFile, CFSwapInt32(arch->offset));
                } else {
                    inject_dylib(binaryFile, CFSwapInt32(arch->offset));
                }
                arch++;
            }
            break;
        }
        case MH_CIGAM_64:
        case MH_MAGIC_64:
        {
            NSLog(@"Thin 64bit binary!");
            inject_dylib_64(binaryFile, 0);
            break;
        }
        case MH_CIGAM:
        case MH_MAGIC:
        {
            NSLog(@"Thin 32bit binary!");
            inject_dylib_64(binaryFile, 0);
            break;
        }
        default:
        {
            NSLog(@"Error: Unknown architecture detected");
            exit(1);
        }
    }
    
    NSLog(@"Injection completed!");
    fclose(binaryFile);
}

void help_and_exit(NSString* cmd)
{
    NSLog(@"Usage: 1. %@ binary_path dylib_path", cmd);
    NSLog(@"       2. copy dylib into folder where binary stays");
    NSLog(@"       3. resign dylib and binary if needed");
    exit(1);
}

int main(int argc, const char * argv[])
{
    NSString* cmd = [[NSString stringWithUTF8String:argv[0]] lastPathComponent];

    if (argc != 3) {
        help_and_exit(cmd);
    }

    NSString* binary_path = [NSString stringWithUTF8String:argv[1]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:binary_path]) {
        help_and_exit(cmd);
    }

    NSString* dylib_path = [NSString stringWithUTF8String:argv[2]];
    NSString* dylib = [dylib_path lastPathComponent];
    DYLIB_PATH = [NSString stringWithFormat:@"@executable_path/%@", dylib];

    inject_file(binary_path, DYLIB_PATH);

    NSLog(@"\nRemember to copy %@ into %@", dylib, [binary_path stringByDeletingLastPathComponent]);

    return 0;
}

