# Redpanda KVStore Demo

This demo showcases a proof of concept of a KVStore built into Redpanda broker, which provides a key-value store interface on top of Kafka topics with tiered storage.

## Overview

Redpanda KVStore allows you to use Kafka topics as distributed key-value stores with:
- Atomic writes with preconditions (CAS operations)
- Batch get operations for efficient lookups
- Range scans over keys in lexicographical order
- Built-in tiered storage integration
- Both HTTP API and rpk CLI access

## Prerequisites

- Docker and Docker Compose
- curl (for HTTP API examples)
- Base64 encoding/decoding utilities

## Getting Started

### 1. Start the Redpanda cluster

```bash
docker compose up -d
```

This starts:
- Redpanda broker with kvstore enabled (ports: 19092 for Kafka, 18082 for HTTP Proxy)
- MinIO for tiered storage backend
- Redpanda Console on http://localhost:8081

### 2. Create a kvstore-enabled topic

```bash
docker compose exec redpanda-0 /opt/redpanda/bin/rpk topic create example-topic -c 'redpanda.kvstore=cloud'
```

The `redpanda.kvstore=cloud` property enables kvstore functionality on the topic.

### 3. Run the demo script

```bash
./demo.sh
```

This demonstrates producing key-value records and querying them via the kvstore API.

## HTTP API Examples

The HTTP Proxy runs on `http://localhost:18082`.

**API Format**: The REST endpoints use Proto JSON format based on the protobuf definitions in [`redpanda.core.rest.v1`](https://github.com/rockwotj/redpanda/blob/kvstore-topic/proto/redpanda/core/rest/v1/kvstore.proto). While the protobuf definitions use `bytes` type for keys and values, the HTTP JSON API requires base64-encoded strings.

### Write Operations

#### Simple Put

Write a single key-value pair:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/write \
  -H "Content-Type: application/json" \
  -d '{
    "puts": [
      {
        "key": "Zm9v",
        "value": "YmFy"
      }
    ]
  }'
```

(Where `Zm9v` = base64("foo") and `YmFy` = base64("bar"))

#### Atomic Batch Write

Write multiple key-value pairs atomically:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/write \
  -H "Content-Type: application/json" \
  -d '{
    "puts": [
      {
        "key": "dXNlcjoxMjM=",
        "value": "eyJuYW1lIjoiQWxpY2UiLCJhZ2UiOjMwfQ=="
      },
      {
        "key": "dXNlcjoxMjQ=",
        "value": "eyJuYW1lIjoiQm9iIiwiYWdlIjoyNX0="
      },
      {
        "key": "Y291bnRlcg==",
        "value": "MTA="
      }
    ]
  }'
```

#### Conditional Put (if-not-exists)

Only write if the key does not exist:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/write \
  -H "Content-Type: application/json" \
  -d '{
    "puts": [
      {
        "key": "bG9jaw==",
        "value": "b3duZWQ=",
        "precondition": {
          "ifExists": {
            "exists": false
          }
        }
      }
    ]
  }'
```

#### Conditional Put (if-matches)

Only update if the current value matches a specific SHA-256 hash:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/write \
  -H "Content-Type: application/json" \
  -d '{
    "puts": [
      {
        "key": "Y291bnRlcg==",
        "value": "MTE=",
        "precondition": {
          "ifMatches": {
            "sha256Hash": "4a44dc15364204a80fe80e9039455cc1608281820fe2b24f1e5233ade6af1dd5"
          }
        }
      }
    ]
  }'
```

#### Delete Operations

Delete keys atomically with puts:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/write \
  -H "Content-Type: application/json" \
  -d '{
    "puts": [
      {
        "key": "bmV3S2V5",
        "value": "bmV3VmFsdWU="
      }
    ],
    "deletes": [
      {
        "key": "b2xkS2V5"
      }
    ]
  }'
```

### Read Operations

#### Batch Get

Retrieve specific keys:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/batch_get \
  -H "Content-Type: application/json" \
  -d '{
    "keys": [
      "Zm9v",
      "dXNlcjoxMjM=",
      "Y291bnRlcg=="
    ]
  }'
```

Response:
```json
{
  "results": [
    {
      "key": "Zm9v",
      "value": "YmFy"
    },
    {
      "key": "dXNlcjoxMjM=",
      "value": "eyJuYW1lIjoiQWxpY2UiLCJhZ2UiOjMwfQ=="
    }
  ]
}
```

Keys not found are omitted from the response.

#### Range Scan

Scan all keys in lexicographical order:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/scan \
  -H "Content-Type: application/json" \
  -d '{
    "limit": 100
  }'
```

Scan a specific key range:

```bash
curl -X POST http://localhost:18082/kvstore/example-topic/partition/0/scan \
  -H "Content-Type: application/json" \
  -d '{
    "startKey": "dXNlcjo=",
    "endKey": "dXNlcjp6enp6",
    "limit": 50
  }'
```

Response:
```json
{
  "entries": [
    {
      "key": "dXNlcjoxMjM=",
      "value": "eyJuYW1lIjoiQWxpY2UiLCJhZ2UiOjMwfQ=="
    },
    {
      "key": "dXNlcjoxMjQ=",
      "value": "eyJuYW1lIjoiQm9iIiwiYWdlIjoyNX0="
    }
  ]
}
```

## rpk CLI Examples

The demo script demonstrates rpk commands for kvstore operations:

### Get a single key

```bash
docker compose exec redpanda-0 /opt/redpanda/bin/rpk kvstore get example-topic foo
```

### Scan all keys

```bash
docker compose exec redpanda-0 /opt/redpanda/bin/rpk kvstore scan example-topic
```

## Helper Script for Base64 Encoding

```bash
# Encode key/value for use in curl commands
echo -n "mykey" | base64    # Output: bXlrZXk=
echo -n "myvalue" | base64  # Output: bXl2YWx1ZQ==

# Decode response values
echo "YmFy" | base64 -d     # Output: bar
```

## Architecture Notes

- **Partition-level operations**: All kvstore operations are scoped to a specific topic partition
- **Atomic writes**: All puts and deletes in a single write request are applied atomically - either all succeed or all fail
- **Strong consistency**: Operations are strongly consistent within a partition with Kafka's durability guarantees
- **Tiered storage**: KVStore requires topics with cloud storage enabled (`redpanda.kvstore=cloud`)
- **Key size limit**: Maximum key size is 16 KiB
- **Message size**: The entire serialized batch must be less than the topic's `max.message.bytes` configuration
- **Scan limits**: Default scan limit is 500 entries, maximum is 1000
- **Lexicographical ordering**: All scan operations return results in lexicographical byte order

### Protobuf Definitions

The HTTP API is defined using Protocol Buffers in the `redpanda.core.rest.v1` package:

- **KVStoreWriteRequest/Response**: Atomic batch writes with optional preconditions
- **KVStoreGetRequest/Response**: Batch retrieval of specific keys
- **KVStoreScanRequest/Response**: Range scans over key ranges

Preconditions support:
- **IfExists**: Check if a key exists or doesn't exist before writing
- **IfMatches**: Compare-and-swap using hex-encoded SHA-256 hash of the current value

See the [full protobuf definition](https://github.com/rockwotj/redpanda/blob/kvstore-topic/proto/redpanda/core/rest/v1/kvstore.proto) for implementation details.

## Use Cases

- Distributed configuration management
- Session storage with TTL via Kafka retention
- Metadata indexing for streaming data
- Lightweight state storage for stream processing
- Cache with persistence and replication

## Stopping the Demo

```bash
docker compose down
```

To remove all volumes:

```bash
docker compose down -v
```

## Additional Resources

- [Redpanda Documentation](https://docs.redpanda.com/)
- Redpanda Console: http://localhost:8081
- MinIO Console: http://localhost:9001 (credentials: minio/minio123)
