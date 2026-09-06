import Foundation

/// Minimal DER support for PKCS#1 RSAPublicKey (SEQUENCE { INTEGER n, INTEGER e }),
/// the external representation the Security framework uses for RSA public keys.
enum DER {
    static func parseRSAPublicKey(_ der: Data) throws -> (n: Data, e: Data) {
        var reader = Reader(der)
        try reader.expect(tag: 0x30)
        _ = try reader.readLength()
        let n = try reader.readInteger()
        let e = try reader.readInteger()
        return (n, e)
    }

    static func encodeRSAPublicKey(n: Data, e: Data) -> Data {
        sequence(integer(n) + integer(e))
    }

    // MARK: - Writer

    private static func integer(_ value: Data) -> Data {
        var body = value
        if let first = body.first, first & 0x80 != 0 {
            body.insert(0x00, at: body.startIndex)
        }
        return Data([0x02]) + length(body.count) + body
    }

    private static func sequence(_ content: Data) -> Data {
        Data([0x30]) + length(content.count) + content
    }

    private static func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    // MARK: - Reader

    private struct Reader {
        private let bytes: [UInt8]
        private var index = 0

        init(_ data: Data) {
            bytes = [UInt8](data)
        }

        mutating func expect(tag: UInt8) throws {
            guard try readByte() == tag else { throw SIOPError.derParsingFailed }
        }

        mutating func readInteger() throws -> Data {
            try expect(tag: 0x02)
            let count = try readLength()
            var value = try readBytes(count)
            while value.count > 1, value.first == 0x00 {
                value = value.dropFirst()
            }
            return Data(value)
        }

        mutating func readLength() throws -> Int {
            let first = try readByte()
            guard first & 0x80 != 0 else { return Int(first) }
            let byteCount = Int(first & 0x7F)
            guard byteCount > 0, byteCount <= 4 else { throw SIOPError.derParsingFailed }
            var value = 0
            for _ in 0..<byteCount {
                value = value << 8 | Int(try readByte())
            }
            return value
        }

        private mutating func readByte() throws -> UInt8 {
            guard index < bytes.count else { throw SIOPError.derParsingFailed }
            defer { index += 1 }
            return bytes[index]
        }

        private mutating func readBytes(_ count: Int) throws -> Data {
            guard count >= 0, index + count <= bytes.count else { throw SIOPError.derParsingFailed }
            defer { index += count }
            return Data(bytes[index..<index + count])
        }
    }
}
