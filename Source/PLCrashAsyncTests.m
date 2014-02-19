/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2008-2009 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "GTMSenTestCase.h"
#import "PLCrashAsync.h"

#import <fcntl.h>
#import <sys/stat.h>

@interface PLCrashAsyncTests : SenTestCase {
@private
    /* Path to test output file */
    NSString *_outputFile;

    /* Open output file descriptor */
    int _testFd;
}

@end


@implementation PLCrashAsyncTests

- (void) setUp {
    /* Create a temporary output file */
    _outputFile = [[NSTemporaryDirectory() stringByAppendingString: [[NSProcessInfo processInfo] globallyUniqueString]] retain];

    _testFd = open([_outputFile UTF8String], O_RDWR|O_CREAT|O_EXCL, 0644);
    STAssertTrue(_testFd >= 0, @"Could not open test output file");
}

- (void) tearDown {
    NSError *error;

    /* Close the file (it may already be closed) */
    close(_testFd);

    /* Delete the file */
    STAssertTrue([[NSFileManager defaultManager] removeItemAtPath: _outputFile error: &error], @"Could not remove log file");
    [_outputFile release];
}

- (void) testByteOrderDetection {
    if (OSHostByteOrder() == OSLittleEndian) {
        STAssertEquals(plcrash_async_byteorder_little_endian(), &plcrash_async_byteorder_direct, @"Incorrect byte order");
        STAssertEquals(plcrash_async_byteorder_big_endian(), &plcrash_async_byteorder_swapped, @"Incorrect byte order");
    } else if (OSHostByteOrder() == OSBigEndian) {
        STAssertEquals(plcrash_async_byteorder_big_endian(), &plcrash_async_byteorder_direct, @"Incorrect byte order");
        STAssertEquals(plcrash_async_byteorder_little_endian(), &plcrash_async_byteorder_swapped, @"Incorrect byte order");
    } else {
        STFail(@"Unknown byte order");
    }
}

- (void) test_readAddr {
    const char bytes[] = "Hello";
    char dest[sizeof(bytes)];
    
    // Verify that a good read succeeds
    plcrash_async_read_addr(mach_task_self(), (pl_vm_address_t) bytes, dest, sizeof(dest));
    STAssertTrue(strcmp(bytes, dest) == 0, @"Read was not performed");
    
    // Verify that reading off the page at 0x0 fails
    STAssertNotEquals(KERN_SUCCESS, plcrash_async_read_addr(mach_task_self(), 0, dest, sizeof(bytes)), @"Bad read was performed");
}


- (void) testApplyAddress {
    pl_vm_address_t result;
    
    /* Verify standard operation */
    STAssertTrue(plcrash_async_address_apply_offset(1, 1, &result), @"Failed to apply offset");
    STAssertEquals((pl_vm_address_t)2, result, @"Incorrect address returned");
    
    /* Verify negative offset handling */
    STAssertTrue(plcrash_async_address_apply_offset(1, -1, &result), @"Failed to apply offset");
    STAssertEquals((pl_vm_address_t)0, result, @"Incorrect address returned");

    /* Verify that overflow is safely handled */
    STAssertFalse(plcrash_async_address_apply_offset(PL_VM_ADDRESS_MAX, 1, &result), @"Bad adddress was accepted");
    STAssertFalse(plcrash_async_address_apply_offset(1, -2, &result), @"Bad adddress was accepted");
}

- (void) testTaskMemcpyAddr {
    const char bytes[] = "Hello";
    char dest[sizeof(bytes)];
    
    // Verify that a good read succeeds
    plcrash_async_task_memcpy(mach_task_self(), (pl_vm_address_t) bytes, 1, dest, sizeof(dest));
    STAssertTrue(strcmp(bytes+1, dest) == 0, @"Read was not performed");
    
    // Verify that reading off the page at 0x0 fails
    STAssertNotEquals(PLCRASH_ESUCCESS, plcrash_async_task_memcpy(mach_task_self(), 0, 0, dest, sizeof(bytes)), @"Bad read was performed");
    
    // Verify that overflow is safely handled
    STAssertEquals(PLCRASH_ENOMEM, plcrash_async_task_memcpy(mach_task_self(), PL_VM_ADDRESS_MAX, 1, dest, sizeof(bytes)), @"Bad read was performed");
}

- (void) testTaskReadInt {
    const plcrash_async_byteorder_t *byteorder = &plcrash_async_byteorder_swapped;
    union test_data {
        uint8_t u8;
        uint16_t u16;
        uint32_t u32;
        uint64_t u64;
    };
    union test_data src;
    union test_data dest;
    src.u64 = 0xCAFEF00DDEADBEEFULL;
    
    STAssertEquals(PLCRASH_ESUCCESS, plcrash_async_task_read_uint64(mach_task_self(), byteorder, &src, 0, &dest.u64), @"Failed to read value");
    STAssertEquals(byteorder->swap64(dest.u64), src.u64, @"Incorrect value read");
    
    STAssertEquals(PLCRASH_ESUCCESS, plcrash_async_task_read_uint32(mach_task_self(), byteorder, &src, 0, &dest.u32), @"Failed to read value");
    STAssertEquals(byteorder->swap32(dest.u32), src.u32, @"Incorrect value read");
    
    STAssertEquals(PLCRASH_ESUCCESS, plcrash_async_task_read_uint16(mach_task_self(), byteorder, &src, 0, &dest.u16), @"Failed to read value");
    STAssertEquals(byteorder->swap16(dest.u16), src.u16, @"Incorrect value read");
    
    STAssertEquals(PLCRASH_ESUCCESS, plcrash_async_task_read_uint8(mach_task_self(), &src, 0, &dest.u8), @"Failed to read value");
    STAssertEquals(dest.u8, src.u8, @"Incorrect value read");
}

- (void) testStrlen {
    STAssertEquals(strlen(""), plcrash_async_strlen(""), @"Empty string should have a zero length");
    STAssertEquals(strlen("Hello"), plcrash_async_strlen("Hello"), @"Incorrect string length");
}

- (void) testStrcmp {
    STAssertEquals(0, plcrash_async_strcmp("s1", "s1"), @"Strings should be equal");
    STAssertTrue(plcrash_async_strcmp("s1", "s2") < 0, @"Strings compared incorrectly");
    STAssertTrue(plcrash_async_strcmp("s2", "s1") > 0, @"Strings compared incorrectly");
    
    /* If these don't crash, success. Of course, it these probably won't crash even if they do over-read; we should
     * probably modify these to sit on the edge of a page boundary. */
    STAssertTrue(plcrash_async_strcmp("longer", "s") != 0, @"");
    STAssertTrue(plcrash_async_strcmp("s", "longer") != 0, @"");
}

- (void) testStrncmp {
    STAssertEquals(0, plcrash_async_strncmp("s1", "s1", 42), @"Strings should be equal");
    STAssertTrue(plcrash_async_strncmp("s1", "s2", 42) < 0, @"Strings compared incorrectly");
    STAssertTrue(plcrash_async_strncmp("s2", "s1", 42) > 0, @"Strings compared incorrectly");
    
    /* If these don't crash, success. Of course, it these probably won't crash even if they do over-read */
    STAssertTrue(plcrash_async_strncmp("longer", "s", 9999999) != 0, @"");
    STAssertTrue(plcrash_async_strncmp("s", "longer", 9999999) != 0, @"");
    
    /* Make sure the "n" works */
    STAssertEquals(plcrash_async_strncmp("aaaaaaaaaa", "abbbbbbbbb", 1), 0, @"String prefixes should be equal");
    STAssertTrue(plcrash_async_strncmp("aaaaaaaaaa", "abbbbbbbbb", 9) < 0, @"String prefixes should be equal");
    STAssertEquals(plcrash_async_strncmp("aaaaaaaaaa", "aaaaaaaaab", 9), 0, @"String prefixes should be equal");
}

- (void) testMemcpy {
    size_t size = 1024;
    uint8_t template[size];
    uint8_t src[size+1];
    uint8_t dest[size+1];

    /* Create our template. We don't use the template as the source, as it's possible the memcpy implementation
     * could modify src in error, while validation could still succeed if src == dest. */
    memset_pattern4(template, (const uint8_t[]){ 0xC, 0xA, 0xF, 0xE }, size);
    memcpy(src, template, size);

    /* Add mismatched sentinals to the destination and src; serves as a simple check for overrun on write. */
    src[1024] = 0xD;
    dest[1024] = 0xB;

    plcrash_async_memcpy(dest, src, size);

    STAssertTrue(memcmp(template, dest, size) == 0, @"The copied destination does not match the source");
    STAssertTrue(dest[1024] == (uint8_t)0xB, @"Sentinal was overwritten (0x%" PRIX8 ")", dest[1024]);
}

- (void) testMemset {
    size_t size = 1024;
    uint8_t template[size];
    uint8_t dest[size+1];
    
    /* Create our template. */
    memset(template, 0xAB, size);
    
    /* Add mismatched sentinals to the destination; serves as a simple check for overrun on write. */
    dest[1024] = 0xB;
    
    plcrash_async_memset(dest, template[0], size);
    
    STAssertTrue(memcmp(template, dest, size) == 0, @"The copied destination does not match the source");
    STAssertTrue(dest[1024] == (uint8_t)0xB, @"Sentinal was overwritten (0x%" PRIX8 ")", dest[1024]);
}

@end
