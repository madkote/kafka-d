﻿module kafkad.config;

struct Configuration {
    /// maximum time to wait for messages in ms
    int consumerMaxWaitTime = 100;
    /// minimum number of bytes to accumulate on the server before returning messages
    int consumerMinBytes = 1;
    /// maximum number of bytes to include in the message set
    int consumerMaxBytes = 1048576;
    /// maximum number of bytes in the consumer message queue, must be greater or equal to consumerMaxBytes
    int consumerQueueMaxBytes = 10485760;
    /// number of retries to perform when refreshing the metadata, 0 = retry infinitely
    int metadataRefreshRetryCount = 3;
    /// time to wait between retries when refreshing the metadata
    int metadataRefreshRetryTimeout = 1000;
}