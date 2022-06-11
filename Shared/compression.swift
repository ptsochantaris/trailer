//  Tweaked from Data+Compression:
//  Created by Lee Morgan on 7/17/15.
//  Copyright © 2015 Lee Morgan. All rights reserved.

import Compression
import Foundation

extension Data {
    enum CompressionOperation {
        case compress
        case decompress
    }

    func data(operation: CompressionOperation) -> Data? {
        guard !isEmpty else {
            return nil
        }

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer {
            streamPtr.deallocate()
        }

        let flags: Int32
        let op: compression_stream_operation
        switch operation {
        case .compress:
            op = COMPRESSION_STREAM_ENCODE
            flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
        case .decompress:
            op = COMPRESSION_STREAM_DECODE
            flags = 0
        }

        var stream = streamPtr.pointee
        var status = compression_stream_init(&stream, op, COMPRESSION_LZFSE)
        guard status != COMPRESSION_STATUS_ERROR else {
            return nil
        }

        defer {
            compression_stream_destroy(&stream)
        }

        return withUnsafeBytes { bytes -> Data? in
            guard let base = bytes.baseAddress else { return nil }

            // setup the stream's source
            stream.src_ptr = base.assumingMemoryBound(to: UInt8.self)
            stream.src_size = count

            // setup the stream's output buffer
            // we use a temporary buffer to store the data as it's compressed
            let dstBufferSize: size_t = 4096
            let dstBufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
            defer {
                dstBufferPtr.deallocate()
            }
            stream.dst_ptr = dstBufferPtr
            stream.dst_size = dstBufferSize
            // and we store the output in a mutable data object
            var outputData = Data()

            repeat {
                status = compression_stream_process(&stream, flags)

                switch status {
                case COMPRESSION_STATUS_OK:
                    // Going to call _process at least once more, so prepare for that
                    if stream.dst_size == 0 {
                        // Output buffer full…

                        // Write out to outputData
                        outputData.append(dstBufferPtr, count: dstBufferSize)

                        // Re-use dstBuffer
                        stream.dst_ptr = dstBufferPtr
                        stream.dst_size = dstBufferSize
                    }

                case COMPRESSION_STATUS_END:
                    // We are done, just write out the output buffer if there's anything in it
                    if stream.dst_ptr > dstBufferPtr {
                        outputData.append(dstBufferPtr, count: stream.dst_ptr - dstBufferPtr)
                    }

                case COMPRESSION_STATUS_ERROR:
                    return nil

                default:
                    break
                }

            } while status == COMPRESSION_STATUS_OK

            return outputData
        }
    }
}
