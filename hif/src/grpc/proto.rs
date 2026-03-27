//! Protobuf encoding and decoding utilities.
//!
//! This module provides helpers for manual protobuf encoding/decoding
//! without requiring code generation.
#![allow(dead_code)]

/// Wire types for protobuf encoding.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum WireType {
    Varint = 0,
    Fixed64 = 1,
    LengthDelimited = 2,
    Fixed32 = 5,
}

impl WireType {
    /// Get wire type from a tag byte.
    pub fn from_tag(tag: u64) -> Option<Self> {
        match tag & 0x7 {
            0 => Some(WireType::Varint),
            1 => Some(WireType::Fixed64),
            2 => Some(WireType::LengthDelimited),
            5 => Some(WireType::Fixed32),
            _ => None,
        }
    }
}

/// Protobuf encoder.
#[derive(Debug, Default)]
pub struct Encoder {
    buf: Vec<u8>,
}

impl Encoder {
    /// Create a new encoder.
    pub fn new() -> Self {
        Self { buf: Vec::new() }
    }

    /// Create an encoder with pre-allocated capacity.
    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            buf: Vec::with_capacity(capacity),
        }
    }

    /// Encode a varint.
    pub fn write_varint(&mut self, mut value: u64) {
        while value >= 0x80 {
            self.buf.push((value as u8 & 0x7f) | 0x80);
            value >>= 7;
        }
        self.buf.push(value as u8);
    }

    /// Encode a field key.
    pub fn write_key(&mut self, field_number: u32, wire_type: WireType) {
        let key = ((field_number as u64) << 3) | (wire_type as u64);
        self.write_varint(key);
    }

    /// Encode a bytes/string field.
    pub fn write_bytes_field(&mut self, field_number: u32, value: &[u8]) {
        self.write_key(field_number, WireType::LengthDelimited);
        self.write_varint(value.len() as u64);
        self.buf.extend_from_slice(value);
    }

    /// Encode a string field.
    pub fn write_string_field(&mut self, field_number: u32, value: &str) {
        self.write_bytes_field(field_number, value.as_bytes());
    }

    /// Encode a varint field.
    pub fn write_varint_field(&mut self, field_number: u32, value: u64) {
        self.write_key(field_number, WireType::Varint);
        self.write_varint(value);
    }

    /// Encode a bool field.
    pub fn write_bool_field(&mut self, field_number: u32, value: bool) {
        self.write_varint_field(field_number, if value { 1 } else { 0 });
    }

    /// Encode an embedded message field.
    pub fn write_message_field(&mut self, field_number: u32, message: &[u8]) {
        self.write_bytes_field(field_number, message);
    }

    /// Encode a fixed64 field.
    pub fn write_fixed64_field(&mut self, field_number: u32, value: u64) {
        self.write_key(field_number, WireType::Fixed64);
        self.buf.extend_from_slice(&value.to_le_bytes());
    }

    /// Encode a fixed32 field.
    pub fn write_fixed32_field(&mut self, field_number: u32, value: u32) {
        self.write_key(field_number, WireType::Fixed32);
        self.buf.extend_from_slice(&value.to_le_bytes());
    }

    /// Get the encoded bytes.
    pub fn finish(self) -> Vec<u8> {
        self.buf
    }

    /// Get the current length.
    pub fn len(&self) -> usize {
        self.buf.len()
    }

    /// Check if empty.
    pub fn is_empty(&self) -> bool {
        self.buf.is_empty()
    }
}

/// Protobuf decoder.
#[derive(Debug)]
pub struct Decoder<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Decoder<'a> {
    /// Create a new decoder.
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    /// Check if at end of data.
    pub fn eof(&self) -> bool {
        self.pos >= self.data.len()
    }

    /// Get current position.
    pub fn position(&self) -> usize {
        self.pos
    }

    /// Get remaining bytes.
    pub fn remaining(&self) -> usize {
        self.data.len().saturating_sub(self.pos)
    }

    /// Read a varint.
    pub fn read_varint(&mut self) -> Option<u64> {
        let mut value: u64 = 0;
        let mut shift = 0;

        while self.pos < self.data.len() {
            let byte = self.data[self.pos];
            self.pos += 1;

            value |= ((byte & 0x7f) as u64) << shift;

            if (byte & 0x80) == 0 {
                return Some(value);
            }

            shift += 7;
            if shift >= 64 {
                return None;
            }
        }

        None
    }

    /// Read a field tag.
    pub fn read_tag(&mut self) -> Option<(u32, WireType)> {
        let tag = self.read_varint()?;
        let field_number = (tag >> 3) as u32;
        let wire_type = WireType::from_tag(tag)?;
        Some((field_number, wire_type))
    }

    /// Read bytes (length-delimited).
    pub fn read_bytes(&mut self) -> Option<&'a [u8]> {
        let len = self.read_varint()? as usize;
        if self.pos + len > self.data.len() {
            return None;
        }
        let result = &self.data[self.pos..self.pos + len];
        self.pos += len;
        Some(result)
    }

    /// Read a string (length-delimited).
    pub fn read_string(&mut self) -> Option<&'a str> {
        let bytes = self.read_bytes()?;
        std::str::from_utf8(bytes).ok()
    }

    /// Skip a field based on wire type.
    pub fn skip_field(&mut self, wire_type: WireType) -> bool {
        match wire_type {
            WireType::Varint => self.read_varint().is_some(),
            WireType::Fixed64 => {
                if self.pos + 8 <= self.data.len() {
                    self.pos += 8;
                    true
                } else {
                    false
                }
            }
            WireType::LengthDelimited => self.read_bytes().is_some(),
            WireType::Fixed32 => {
                if self.pos + 4 <= self.data.len() {
                    self.pos += 4;
                    true
                } else {
                    false
                }
            }
        }
    }

    /// Read a fixed64.
    pub fn read_fixed64(&mut self) -> Option<u64> {
        if self.pos + 8 > self.data.len() {
            return None;
        }
        let result = u64::from_le_bytes(self.data[self.pos..self.pos + 8].try_into().ok()?);
        self.pos += 8;
        Some(result)
    }

    /// Read a fixed32.
    pub fn read_fixed32(&mut self) -> Option<u32> {
        if self.pos + 4 > self.data.len() {
            return None;
        }
        let result = u32::from_le_bytes(self.data[self.pos..self.pos + 4].try_into().ok()?);
        self.pos += 4;
        Some(result)
    }

    /// Read a bool.
    pub fn read_bool(&mut self) -> Option<bool> {
        Some(self.read_varint()? != 0)
    }
}

/// Iterator over protobuf fields.
pub struct FieldIterator<'a> {
    decoder: Decoder<'a>,
}

impl<'a> FieldIterator<'a> {
    /// Create a new field iterator.
    pub fn new(data: &'a [u8]) -> Self {
        Self {
            decoder: Decoder::new(data),
        }
    }
}

impl<'a> Iterator for FieldIterator<'a> {
    type Item = (u32, WireType, &'a [u8]);

    fn next(&mut self) -> Option<Self::Item> {
        if self.decoder.eof() {
            return None;
        }

        let (field_number, wire_type) = self.decoder.read_tag()?;
        let start = self.decoder.pos;

        let data = match wire_type {
            WireType::Varint => {
                self.decoder.read_varint()?;
                &self.decoder.data[start..self.decoder.pos]
            }
            WireType::Fixed64 => {
                if self.decoder.pos + 8 > self.decoder.data.len() {
                    return None;
                }
                self.decoder.pos += 8;
                &self.decoder.data[start..self.decoder.pos]
            }
            WireType::LengthDelimited => self.decoder.read_bytes()?,
            WireType::Fixed32 => {
                if self.decoder.pos + 4 > self.decoder.data.len() {
                    return None;
                }
                self.decoder.pos += 4;
                &self.decoder.data[start..self.decoder.pos]
            }
        };

        Some((field_number, wire_type, data))
    }
}

/// Decode a varint from bytes.
pub fn decode_varint(data: &[u8]) -> u64 {
    let mut decoder = Decoder::new(data);
    decoder.read_varint().unwrap_or(0)
}

/// Decode a string from bytes.
pub fn decode_string(data: &[u8]) -> String {
    String::from_utf8_lossy(data).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_varint() {
        let mut encoder = Encoder::new();
        encoder.write_varint(300);
        assert_eq!(encoder.finish(), vec![0xAC, 0x02]);
    }

    #[test]
    fn test_encode_string_field() {
        let mut encoder = Encoder::new();
        encoder.write_string_field(1, "testing");
        let bytes = encoder.finish();

        // Field 1, wire type 2 (length-delimited) = 0x0A
        // Length 7 = 0x07
        // "testing" = 0x74 0x65 0x73 0x74 0x69 0x6E 0x67
        assert_eq!(bytes[0], 0x0A);
        assert_eq!(bytes[1], 7);
        assert_eq!(&bytes[2..], b"testing");
    }

    #[test]
    fn test_decode_varint() {
        let mut decoder = Decoder::new(&[0xAC, 0x02]);
        assert_eq!(decoder.read_varint(), Some(300));
    }

    #[test]
    fn test_decode_string() {
        let data = [0x07, b't', b'e', b's', b't', b'i', b'n', b'g'];
        let mut decoder = Decoder::new(&data);
        assert_eq!(decoder.read_string(), Some("testing"));
    }

    #[test]
    fn test_field_iterator() {
        let mut encoder = Encoder::new();
        encoder.write_string_field(1, "hello");
        encoder.write_varint_field(2, 42);
        encoder.write_string_field(3, "world");
        let bytes = encoder.finish();

        let fields: Vec<_> = FieldIterator::new(&bytes).collect();
        assert_eq!(fields.len(), 3);
        assert_eq!(fields[0].0, 1); // field 1
        assert_eq!(fields[1].0, 2); // field 2
        assert_eq!(fields[2].0, 3); // field 3
    }

    #[test]
    fn test_roundtrip() {
        let mut encoder = Encoder::new();
        encoder.write_string_field(1, "test");
        encoder.write_varint_field(2, 12345);
        encoder.write_bool_field(3, true);
        let bytes = encoder.finish();

        let mut decoder = Decoder::new(&bytes);

        // Field 1
        let (num, wt) = decoder.read_tag().unwrap();
        assert_eq!(num, 1);
        assert_eq!(wt, WireType::LengthDelimited);
        assert_eq!(decoder.read_string(), Some("test"));

        // Field 2
        let (num, wt) = decoder.read_tag().unwrap();
        assert_eq!(num, 2);
        assert_eq!(wt, WireType::Varint);
        assert_eq!(decoder.read_varint(), Some(12345));

        // Field 3
        let (num, wt) = decoder.read_tag().unwrap();
        assert_eq!(num, 3);
        assert_eq!(wt, WireType::Varint);
        assert_eq!(decoder.read_bool(), Some(true));

        assert!(decoder.eof());
    }
}
