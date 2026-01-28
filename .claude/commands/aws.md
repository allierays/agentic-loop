---
description: AWS patterns and best practices. Use when working with S3, Lambda, DynamoDB, IAM, SQS, or other AWS services.
---

# AWS Patterns

Best practices for AWS services. Use these patterns when writing infrastructure or application code that interacts with AWS.

## IAM

### Least Privilege

```json
// ❌ NEVER: Wildcard permissions
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}

// ✅ ALWAYS: Specific actions and resources
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::my-bucket/uploads/*"
}
```

### Service Roles

```typescript
// ❌ NEVER: Use root credentials or long-lived keys
const client = new S3Client({
  credentials: {
    accessKeyId: 'AKIA...',
    secretAccessKey: '...'
  }
});

// ✅ ALWAYS: Use IAM roles (SDK auto-discovers)
const client = new S3Client({ region: 'us-east-1' });
// In Lambda/ECS/EC2 - credentials come from execution role
```

### Cross-Account Access

```json
// Trust policy for cross-account role assumption
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::OTHER_ACCOUNT:role/service-role"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "${external_id}"  // Prevent confused deputy
      }
    }
  }]
}
```

## S3

### Secure Defaults

```typescript
// ✅ Create buckets with secure defaults
const bucket = new s3.Bucket(this, 'Bucket', {
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  encryption: s3.BucketEncryption.S3_MANAGED,
  enforceSSL: true,
  versioned: true,
  removalPolicy: RemovalPolicy.RETAIN  // Don't delete data
});
```

### Presigned URLs

```typescript
// ✅ For temporary access without exposing credentials
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';

// Download URL (15 min expiry)
const downloadUrl = await getSignedUrl(s3Client,
  new GetObjectCommand({ Bucket: bucket, Key: key }),
  { expiresIn: 900 }
);

// Upload URL with constraints
const uploadUrl = await getSignedUrl(s3Client,
  new PutObjectCommand({
    Bucket: bucket,
    Key: `uploads/${userId}/${filename}`,
    ContentType: 'image/jpeg'  // Restrict file type
  }),
  { expiresIn: 300 }
);
```

### Multipart Uploads

```typescript
// ✅ For files > 100MB
import { Upload } from '@aws-sdk/lib-storage';

const upload = new Upload({
  client: s3Client,
  params: { Bucket: bucket, Key: key, Body: stream },
  partSize: 10 * 1024 * 1024,  // 10MB parts
  leavePartsOnError: false      // Clean up on failure
});

upload.on('httpUploadProgress', (progress) => {
  console.log(`${progress.loaded}/${progress.total}`);
});

await upload.done();
```

## Lambda

### Handler Pattern

```typescript
// ✅ Initialize outside handler (reused across invocations)
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';

const ddb = new DynamoDBClient({});  // Cold start only

export const handler = async (event: APIGatewayEvent) => {
  // Handler code uses pre-initialized client
  try {
    const result = await processEvent(event);
    return { statusCode: 200, body: JSON.stringify(result) };
  } catch (error) {
    console.error('Handler error:', error);  // CloudWatch logging
    return { statusCode: 500, body: JSON.stringify({ error: 'Internal error' }) };
  }
};
```

### Environment Variables

```typescript
// ✅ Validate at cold start, not per-request
const TABLE_NAME = process.env.TABLE_NAME;
const QUEUE_URL = process.env.QUEUE_URL;

if (!TABLE_NAME || !QUEUE_URL) {
  throw new Error('Missing required environment variables');
}

export const handler = async (event) => {
  // Use TABLE_NAME, QUEUE_URL directly
};
```

### Timeouts and Memory

```typescript
// ✅ CDK configuration
new lambda.Function(this, 'Handler', {
  runtime: lambda.Runtime.NODEJS_20_X,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('dist'),
  timeout: Duration.seconds(30),    // Always set explicitly
  memorySize: 256,                   // More memory = more CPU
  reservedConcurrentExecutions: 10,  // Prevent runaway scaling
  environment: {
    TABLE_NAME: table.tableName,
    NODE_OPTIONS: '--enable-source-maps'
  }
});
```

### Dead Letter Queues

```typescript
// ✅ Capture failed invocations
const dlq = new sqs.Queue(this, 'DLQ', {
  retentionPeriod: Duration.days(14)
});

new lambda.Function(this, 'Handler', {
  // ...
  deadLetterQueue: dlq,
  retryAttempts: 2
});
```

## DynamoDB

### Table Design

```typescript
// ✅ Single-table design with composite keys
const table = new dynamodb.Table(this, 'Table', {
  partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'SK', type: dynamodb.AttributeType.STRING },
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  pointInTimeRecovery: true,
  encryption: dynamodb.TableEncryption.AWS_MANAGED
});

// Add GSI for access patterns
table.addGlobalSecondaryIndex({
  indexName: 'GSI1',
  partitionKey: { name: 'GSI1PK', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'GSI1SK', type: dynamodb.AttributeType.STRING }
});
```

### Key Patterns

```typescript
// ✅ Composite keys for flexible queries
// User: PK=USER#123, SK=PROFILE
// User's orders: PK=USER#123, SK=ORDER#2024-01-15#456
// Order by ID: GSI1PK=ORDER#456, GSI1SK=ORDER#456

await ddb.put({
  TableName: TABLE_NAME,
  Item: {
    PK: `USER#${userId}`,
    SK: `ORDER#${date}#${orderId}`,
    GSI1PK: `ORDER#${orderId}`,
    GSI1SK: `ORDER#${orderId}`,
    // ... other attributes
  }
});

// Query user's recent orders
await ddb.query({
  TableName: TABLE_NAME,
  KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
  ExpressionAttributeValues: {
    ':pk': `USER#${userId}`,
    ':sk': 'ORDER#'
  },
  ScanIndexForward: false,  // Newest first
  Limit: 10
});
```

### Transactions

```typescript
// ✅ Atomic operations across items
await ddb.transactWrite({
  TransactItems: [
    {
      Update: {
        TableName: TABLE_NAME,
        Key: { PK: `USER#${userId}`, SK: 'BALANCE' },
        UpdateExpression: 'SET balance = balance - :amount',
        ConditionExpression: 'balance >= :amount',
        ExpressionAttributeValues: { ':amount': amount }
      }
    },
    {
      Put: {
        TableName: TABLE_NAME,
        Item: {
          PK: `USER#${userId}`,
          SK: `TXN#${txnId}`,
          amount,
          timestamp: Date.now()
        }
      }
    }
  ]
});
```

## SQS

### Producer Pattern

```typescript
// ✅ Batch sends for efficiency
import { SendMessageBatchCommand } from '@aws-sdk/client-sqs';

const entries = items.map((item, i) => ({
  Id: String(i),
  MessageBody: JSON.stringify(item),
  MessageGroupId: item.groupId,        // For FIFO queues
  MessageDeduplicationId: item.id      // For FIFO queues
}));

// Send in batches of 10 (SQS limit)
for (let i = 0; i < entries.length; i += 10) {
  await sqs.send(new SendMessageBatchCommand({
    QueueUrl: QUEUE_URL,
    Entries: entries.slice(i, i + 10)
  }));
}
```

### Consumer Pattern

```typescript
// ✅ Lambda SQS trigger with partial batch response
export const handler = async (event: SQSEvent) => {
  const failures: SQSBatchItemFailure[] = [];

  for (const record of event.Records) {
    try {
      const body = JSON.parse(record.body);
      await processMessage(body);
    } catch (error) {
      console.error(`Failed: ${record.messageId}`, error);
      failures.push({ itemIdentifier: record.messageId });
    }
  }

  return { batchItemFailures: failures };  // Only retry failed messages
};
```

## Secrets Manager

```typescript
// ✅ Cache secrets, don't fetch per-request
import { GetSecretValueCommand, SecretsManagerClient } from '@aws-sdk/client-secrets-manager';

const sm = new SecretsManagerClient({});
let cachedSecret: string | null = null;

async function getSecret(): Promise<string> {
  if (!cachedSecret) {
    const response = await sm.send(new GetSecretValueCommand({
      SecretId: process.env.SECRET_ARN
    }));
    cachedSecret = response.SecretString!;
  }
  return cachedSecret;
}
```

## Error Handling

```typescript
// ✅ Handle AWS-specific errors
import { ConditionalCheckFailedException } from '@aws-sdk/client-dynamodb';
import { S3ServiceException } from '@aws-sdk/client-s3';

try {
  await ddb.put({ /* ... */, ConditionExpression: 'attribute_not_exists(PK)' });
} catch (error) {
  if (error instanceof ConditionalCheckFailedException) {
    throw new ConflictError('Item already exists');
  }
  throw error;
}

try {
  await s3.getObject({ Bucket, Key });
} catch (error) {
  if (error instanceof S3ServiceException && error.name === 'NoSuchKey') {
    return null;
  }
  throw error;
}
```

## Cost Optimization

```typescript
// ✅ Use appropriate storage classes
new s3.Bucket(this, 'Bucket', {
  lifecycleRules: [{
    transitions: [
      { storageClass: s3.StorageClass.INFREQUENT_ACCESS, transitionAfter: Duration.days(30) },
      { storageClass: s3.StorageClass.GLACIER, transitionAfter: Duration.days(90) }
    ],
    expiration: Duration.days(365)
  }]
});

// ✅ DynamoDB on-demand for unpredictable workloads
billingMode: dynamodb.BillingMode.PAY_PER_REQUEST

// ✅ Lambda ARM64 for better price/performance
architecture: lambda.Architecture.ARM_64
```

## Testing

```typescript
// ✅ Use local emulators for unit tests
// docker run -p 8000:8000 amazon/dynamodb-local

const ddb = new DynamoDBClient({
  endpoint: process.env.DYNAMODB_ENDPOINT || undefined,  // Local in tests
  region: 'us-east-1'
});

// ✅ Or use mocks
import { mockClient } from 'aws-sdk-client-mock';

const ddbMock = mockClient(DynamoDBClient);
ddbMock.on(GetItemCommand).resolves({ Item: { /* ... */ } });
```
