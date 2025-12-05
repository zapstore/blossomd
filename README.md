# Blossom Server

A Dart implementation of a Blossom server following the [Blossom specification](https://github.com/hzrd149/blossom) for storing and serving blobs with Nostr authentication.

## Features

- **SHA-256 Content Addressing**: All blobs are stored and accessed using their SHA-256 hash
- **Nostr Authentication**: Upload and delete operations require valid Nostr event signatures
- **External Authorization**: Upload/Delete access via Zapstore relay check (`/api/v1/accept?pubkey=<npub>`)
- **Blob Ownership**: Track and list blobs owned by each pubkey with the `/list/<pubkey>` endpoint
- **RESTful HTTP API**: Standard HTTP endpoints for blob storage and retrieval
- **SQLite Database**: Persistent storage for blob ownership metadata
- **File Size Limits**: Configurable upload size limits (default: 600MB)
- **Authorization**: Controlled by external relay; no local whitelist management

## Installation

1. **Install Dart SDK** (3.0 or later)
2. **Clone and setup**:
   ```bash
   git clone <repository-url>
   cd blossomd
   dart pub get
   ```

### Dependencies

This implementation uses the following key dependencies:
- **bip340**: For Nostr signature verification (BIP-340 Schnorr signatures)
- **shelf**: HTTP server framework
- **sqlite3**: Database storage for whitelist management
- **crypto**: SHA-256 hashing for content addressing
- **dotenv**: For loading configuration from .env files

## Configuration

Configure the server using a `.env` file or environment variables:

### Using .env file (Recommended)

1. Copy the example configuration file:
   ```bash
   cp env.example .env
   ```

2. Edit `.env` with your settings:
   ```bash
   # Base directory for data storage (database and blob files)
   WORKING_DIR=./data
   
   # HTTP server port
   PORT=3334
   
   # Public server URL (used for generating blob URLs in responses)
   SERVER_URL=http://localhost:3334
   ```

### Configuration Variables

- `WORKING_DIR`: Base directory for data storage (default: `./data`)
- `PORT`: HTTP server port (default: `3334`)
- `SERVER_URL`: Public server URL (default: `http://localhost:<PORT>`)

The server loads configuration in this order:
1. Values from `.env` file (if it exists)
2. Environment variables
3. Default values

## Usage

### Starting the Server

```bash
# First, set up your configuration (one-time setup)
cp env.example .env
# Edit .env with your settings

# Start with .env file configuration
dart run bin/blossomd.dart

# Alternative: Start with environment variables
WORKING_DIR=/var/blossom PORT=8080 dart run bin/blossomd.dart
```

### Authorization

Upload/Delete are allowed only if the external relay returns `{ "accept": true }` for the caller's npub:

```text
GET https://relay.zapstore.dev/api/v1/accept?pubkey=<npub>
```

### Command Line Options

```bash
# Show help
dart run bin/blossomd.dart --help

# Show version
dart run bin/blossomd.dart --version

Authorization is handled by the external relay endpoint. No local whitelist commands.
```

## API Endpoints

### Retrieve Blob
```http
GET /<sha256>
HEAD /<sha256>
```

### Upload Blob
```http
PUT /upload
Authorization: Nostr <base64-encoded-event>
Content-Type: application/octet-stream

<binary-data>
```

### List User Blobs
```http
GET /list/<pubkey>
```

Returns a JSON array of all blobs owned by the specified pubkey. The pubkey can be provided in either hex format (64-character hex string) or npub format (bech32-encoded). Each blob entry includes:
- `sha256`: The SHA-256 hash of the blob
- `size`: File size in bytes
- `type`: MIME type (if provided during upload)
- `uploaded`: Unix timestamp of upload time
- `url`: Full URL to access the blob

Example response:
```json
[
  {
    "sha256": "abcd1234...",
    "size": 12345,
    "type": "image/jpeg",
    "uploaded": 1704067200,
    "url": "https://example.com/abcd1234..."
  }
]
```

### Delete Blob
```http
DELETE /<sha256>
Authorization: Nostr <base64-encoded-event>
```

### Upload Options
```http
HEAD /upload
```

## Nostr Authentication

Upload and delete operations require a Nostr authorization header with a signed event:

```javascript
{
  "kind": 24242,
  "created_at": <timestamp>,
  "tags": [
    ["t", "upload"],
    ["x", "<sha256-hash>"],
    ["m", "<mime-type>"],
    ["expiration", "<timestamp>"]
  ],
  "content": "",
  "pubkey": "<user-pubkey>",
  "id": "<event-id>",
  "sig": "<signature>"
}
```

The event must be base64-encoded and included in the Authorization header:
```
Authorization: Nostr <base64-encoded-event>
```

**Signature Verification**: The server performs proper BIP-340 signature verification on all Nostr events. Invalid signatures will be rejected with appropriate error messages.

## Database Management

The server uses SQLite for storing blob ownership information. The database is automatically created at `<WORKING_DIR>/database.sqlite`.

### Manual Database Access

You can directly access the SQLite database:

```bash
sqlite3 data/database.sqlite
```

```sql
-- View all whitelisted pubkeys
SELECT * FROM whitelist;

-- Add a pubkey manually
INSERT OR REPLACE INTO whitelist (pubkey) VALUES ('pubkey_hex');

-- Remove a pubkey manually
DELETE FROM whitelist WHERE pubkey = 'pubkey_hex';
```

## File Storage

Blobs are stored in a flat directory structure:
```
data/
├── database.sqlite
└── blobs/
    ├── abcd1234...
    ├── cdef5678...
    └── ...
```

## Examples

### Upload a file (with proper Nostr authentication)
```bash
# This requires implementing Nostr event signing in your client
curl -X PUT http://localhost:3334/upload \
  -H "Authorization: Nostr <base64-event>" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @myfile.jpg
```

### Download a file
```bash
curl http://localhost:3334/abc123def456...
```

### Configuration Examples

**Development setup:**
```bash
# Copy the example
cp env.example .env

# Edit .env for development
WORKING_DIR=./data
PORT=3334
SERVER_URL=http://localhost:3334
```

**Production setup:**
```bash
# Edit .env for production
WORKING_DIR=/var/lib/blossom
PORT=8080
SERVER_URL=https://blossom.example.com
```

### Notes
- Server converts hex pubkeys to npub when querying the relay.

## Security Considerations

### Current Security Features
- ✅ **Nostr Signature Verification**: Proper BIP-340 signature verification using the bip340 library
- ✅ **Whitelist-based Access Control**: Binary permission system (whitelisted = allowed, not whitelisted = denied)
- ✅ **Event Expiration Checking**: Time-based authorization validation
- ✅ **File Hash Verification**: SHA-256 content integrity verification
- ✅ **Upload Size Limits**: Configurable file size restrictions
- ✅ **Event Structure Validation**: Proper Nostr event format validation

### Production Requirements
- Use HTTPS in production
- Regular database backups
- Monitor disk space usage
- Implement rate limiting
- Log monitoring and alerting
- Consider adding request throttling
- Implement proper error handling and recovery

## Limitations

1. **Metrics**: No built-in metrics or monitoring endpoints
2. **Clustering**: Single-instance deployment only
3. **Rate Limiting**: No built-in rate limiting (should be added for production)

## Development

### Running Tests
```bash
dart test
```

### Code Analysis
```bash
dart analyze
```

### Building
```bash
dart compile exe bin/blossomd.dart -o blossomd
```

## License

This project is open source. See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Support

For issues and questions, please use the GitHub issue tracker.
