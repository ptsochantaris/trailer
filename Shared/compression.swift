import Compression
import Foundation

extension Data {
    enum Operation {
        case compress
        case decompress

        var params: (flags: Int32, operation: compression_stream_operation) {
            switch self {
            case .compress:
                (Int32(COMPRESSION_STREAM_FINALIZE.rawValue), COMPRESSION_STREAM_ENCODE)
            case .decompress:
                (0, COMPRESSION_STREAM_DECODE)
            }
        }
    }

    func data(operation: Operation) -> Data? {
        if isEmpty {
            return nil
        }

        return withUnsafeBytes { bytes -> Data? in
            guard let base = bytes.baseAddress else { return nil }

            let params = operation.params

            let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer {
                streamPtr.deallocate()
            }

            var stream = streamPtr.pointee
            let status = compression_stream_init(&stream, params.operation, COMPRESSION_LZFSE)
            if status == COMPRESSION_STATUS_ERROR { return nil }
            defer {
                compression_stream_destroy(&stream)
            }

            let dstBufferSize: size_t = 4096
            let dstBufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
            defer {
                dstBufferPtr.deallocate()
            }

            stream.src_ptr = base.assumingMemoryBound(to: UInt8.self)
            stream.src_size = count
            stream.dst_ptr = dstBufferPtr
            stream.dst_size = dstBufferSize

            var outputData = Data()

            while true {
                switch compression_stream_process(&stream, params.flags) {
                case COMPRESSION_STATUS_OK:
                    if stream.dst_size == 0 {
                        outputData.append(dstBufferPtr, count: dstBufferSize)
                        stream.dst_ptr = dstBufferPtr
                        stream.dst_size = dstBufferSize
                    }

                case COMPRESSION_STATUS_END:
                    if stream.dst_ptr > dstBufferPtr {
                        outputData.append(dstBufferPtr, count: stream.dst_ptr - dstBufferPtr)
                    }
                    return outputData

                default: // COMPRESSION_STATUS_ERROR
                    return nil
                }
            }
        }
    }
}
