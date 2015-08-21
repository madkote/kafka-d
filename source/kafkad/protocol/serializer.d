﻿module kafkad.protocol.serializer;

import kafkad.protocol.common;

/* serialize data up to ChunkSize, this is not zero-copy unfortunately, as vibe.d's drivers and kernel may do
 * buffering on their own, however, it should minimize the overhead of many, small write() calls to the driver */

struct Serializer {
    private {
        ubyte* chunk, p, end;
        Stream stream;
    }

    this(Stream stream) {
        chunk = cast(ubyte*)enforce(GC.malloc(ChunkSize, GC.BlkAttr.NO_SCAN));
        p = chunk;
        end = chunk + ChunkSize;
        this.stream = stream;
    }

    void flush() {
        assert(p - chunk);
        stream.write(chunk[0 .. p - chunk]);
        p = chunk;
    }

    void check(size_t needed) {
        pragma(inline, true);
        if (end - p < needed)
            flush();
    }

    void serialize(byte s) {
        check(1);
        *p++ = s;
    }

    void serialize(T)(T s)
        if (is(T == short) || is(T == int) || is(T == long))
    {
        check(T.sizeof);
        version (LittleEndian)
            s = swapEndian(s);
        auto pt = cast(T*)p;
        *pt++ = s;
        p = cast(ubyte*)pt;
    }

    private void serializeSlice(ubyte[] s) {
        auto slice = s;
        if (slice.length > ChunkSize) {
            if (p - chunk)
                flush();
            while (slice.length > ChunkSize) {
                stream.write(slice[0 .. ChunkSize]);
                slice = slice[ChunkSize .. $];
            }
        }
        check(slice.length);
        core.stdc.string.memcpy(p, slice.ptr, slice.length);
        p += slice.length;
    }

    void serialize(string s) {
        enforce(s.length <= short.max, "UTF8 string must not be longer than 32767 bytes");
        serialize(cast(short)s.length);
        serializeSlice(cast(ubyte[])s);
    }

    void serialize(ubyte[] s) {
        enforce(s.length <= int.max, "Byte array must not be larger than 4 GB"); // just in case
        serialize(cast(int)s.length);
        serializeSlice(s);
    }

    private void arrayLength(size_t length) {
        enforce(length <= int.max, "Arrays must not be longer that 2^31 items"); // just in case, maybe set some configurable (and saner) limits?
        serialize(cast(int)length);
    }

    private void request(size_t size, ApiKey apiKey, short apiVersion, int correlationId, string clientId) {
        size += 2 + 2 + 4 + stringSize(clientId);
        serialize(cast(int)size);
        serialize(cast(short)apiKey);
        serialize(apiVersion);
        serialize(correlationId);
        serialize(clientId);
    }

    private enum arrayOverhead = 4; // int32
    private auto stringSize(string s) { return 2 + s.length; } // int16 plus string

    // version 0
    void metadataRequest_v0(int correlationId, string clientId, string[] topics) {
        auto size = arrayOverhead;
        foreach (t; topics)
            size += stringSize(t);
        request(size, ApiKey.MetadataRequest, 0, correlationId, clientId);
        arrayLength(topics.length);
        foreach (t; topics)
            serialize(t);
        flush();
    }

    // version 0
    void fetchRequest_v0(int correlationId, string clientId, TopicPartitions[] topics) {
        auto size = 4 + 4 + 4 + arrayOverhead;
        foreach (ref t; topics) {
            size += stringSize(t.topic) + arrayOverhead + t.partitions.length * (4 + 8 + 4);
        }
        request(size, ApiKey.FetchRequest, 0, correlationId, clientId);
        serialize!int(-1); // ReplicaId
        serialize!int(100); // MaxWaitTime, TODO: configurability, but now these values are same as defaults in librdkafka
        serialize!int(1); // MinBytes
        arrayLength(topics.length);
        foreach (ref t; topics) {
            serialize(t.topic);
            arrayLength(t.partitions.length);
            foreach (ref p; t.partitions) {
                serialize(p.partition);
                serialize(p.offset);
                serialize!int(1048576); // MaxBytes
            }
        }
        flush();
    }
}