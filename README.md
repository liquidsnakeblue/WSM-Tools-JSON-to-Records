# WSM-Tools-JSON-to-Records

[![CI](https://github.com/WeSummitMountains/WSM-Tools-JSON-to-Records/actions/workflows/ci.yml/badge.svg)](https://github.com/WeSummitMountains/WSM-Tools-JSON-to-Records/actions/workflows/ci.yml)
![Salesforce API](https://img.shields.io/badge/Salesforce%20API-62.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

A production-grade, bulk-safe Salesforce invocable action that applies JSON payloads to update header (parent) records and insert/update child records dynamically.

## Overview

This tool allows Flows, Process Builder, and Apex to update any SObject and its children using a simple JSON structure. It's designed for use with Agentforce, LLM integrations, and any scenario where record updates need to be driven by dynamic data.

### Key Features

- **Bulk-Safe**: Processes hundreds of records in a single transaction without hitting governor limits
- **Dynamic**: Works with any standard or custom object - no hardcoded field names
- **FLS-Aware**: Respects field-level security with "skip & warn" behavior
- **Partial Success**: Individual record failures don't block other records
- **Detailed Feedback**: Returns success/failure status, counts, errors, and warnings

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   JsonToRecordsAction                        │
│                  (@InvocableMethod)                          │
│         Thin wrapper: validation + orchestration             │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   JsonToRecordsService                       │
│                   (Business Logic)                           │
│                                                              │
│  Phase 1: Parse JSON ──► Phase 2: Collect Headers ──►       │
│  Phase 3: Collect Children ──► Phase 4: Bulk DML            │
└──────────────┬──────────────────────────┬───────────────────┘
               │                          │
               ▼                          ▼
┌──────────────────────────┐  ┌───────────────────────────────┐
│      SchemaCache         │  │        FieldCaster            │
│  (Cached Describe)       │  │   (Type Conversion)           │
└──────────────────────────┘  └───────────────────────────────┘
```

## Installation

### Deploy to Production/Sandbox

```bash
# Clone the repository
git clone https://github.com/WeSummitMountains/WSM-Tools-JSON-to-Records.git
cd WSM-Tools-JSON-to-Records

# Authorize your org (if not already done)
sf org login web --alias MyOrg

# Deploy
sf project deploy start --source-dir force-app --target-org MyOrg
```

### Deploy to Scratch Org

```bash
# Run the setup script (requires DevHub authorization)
./scripts/scratch-org-setup.sh my-scratch-org
```

## Usage

### In Flow Builder

1. Add an **Action** element
2. Search for **"Apply JSON to Header & Children"**
3. Configure the inputs:
   - **Header Record Id**: The parent record's Id (e.g., `{!$Record.Id}`)
   - **SObject Type API Name**: The object type (e.g., `Opportunity`)
   - **JSON Payload**: Your JSON string

### JSON Payload Format

```json
{
  "header": {
    "StageName": "Proposal/Price Quote",
    "CloseDate": "2025-12-31",
    "NextStep": "Send formal proposal"
  },
  "children": {
    "OpportunityLineItems": [
      {
        "Id": "00kXXXX000000123AAA",
        "Quantity": 10,
        "UnitPrice": 100
      },
      {
        "Quantity": 5,
        "UnitPrice": 50,
        "PricebookEntryId": "01uXXXX000000456BBB"
      }
    ]
  }
}
```

| Key | Description |
|-----|-------------|
| `header` | Object with field API names → values to update on the parent record |
| `children` | Object keyed by **child relationship name** (e.g., `Contacts`, `OpportunityLineItems`) |
| Child with `Id` | Updates the existing child record |
| Child without `Id` | Inserts a new child record (parent FK is set automatically) |

### Output Variables

| Variable | Type | Description |
|----------|------|-------------|
| `success` | Boolean | `true` if the operation completed without errors |
| `message` | String | Human-readable summary |
| `headerUpdated` | Boolean | Whether the header record was modified |
| `childrenInserted` | Integer | Count of child records inserted |
| `childrenUpdated` | Integer | Count of child records updated |
| `errors` | List\<String\> | Detailed error messages (if any) |
| `warnings` | List\<String\> | Warnings for skipped fields/relationships |

### Example Flow Decision

```
IF {!Apply_JSON.success} = true
  → Continue flow
ELSE
  → Log errors: {!Apply_JSON.errors}
```

## Supported Field Types

| Type | Example JSON Value |
|------|-------------------|
| String / Text | `"Hello World"` |
| Number / Integer | `100` or `"100"` |
| Currency / Decimal | `1000.50` or `"1000.50"` |
| Boolean | `true`, `false`, `"true"`, `"1"`, `"yes"` |
| Date | `"2025-12-31"` |
| DateTime | `"2025-12-31T14:30:00Z"` |
| Picklist | `"Closed Won"` |
| Reference (Id) | `"001XXXXXXXXXXXX"` |

## Error Handling

### FLS Violations (Skip & Warn)
Fields that the running user cannot update are **skipped** with a warning:
```
warnings: ["Field 'SecretField__c' is not updateable - skipped"]
```
The operation continues and succeeds if the record itself saves.

### Unknown Fields/Relationships
Unknown fields and relationships are skipped with warnings, not errors.

### DML Failures
If a specific record fails validation rules or triggers, that record's result shows `success: false` with the error message, but other records in the batch continue processing.

## Development

### Project Structure

```
WSM-Tools-JSON-to-Records/
├── force-app/main/default/classes/
│   ├── JsonToRecordsAction.cls      # Invocable entry point
│   ├── JsonToRecordsService.cls     # Core business logic
│   ├── SchemaCache.cls              # Schema caching utility
│   ├── FieldCaster.cls              # Type conversion utility
│   ├── *Test.cls                    # Test classes
│   └── *.cls-meta.xml               # Metadata files
├── config/
│   └── project-scratch-def.json     # Scratch org config
├── scripts/
│   └── scratch-org-setup.sh         # Dev environment setup
├── .github/workflows/
│   └── ci.yml                       # GitHub Actions CI
├── sfdx-project.json
├── README.md
└── LICENSE
```

### Running Tests

```bash
# Run all tests with coverage
sf apex run test --code-coverage --result-format human --wait 10

# Run specific test class
sf apex run test --tests JsonToRecordsActionTest --wait 10
```

### Code Coverage Target

- **Minimum**: 75% (Salesforce requirement)
- **Target**: 85%+

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues, feature requests, or questions:
- Open an issue on [GitHub](https://github.com/WeSummitMountains/WSM-Tools-JSON-to-Records/issues)

---

Built with care by [We Summit Mountains](https://github.com/WeSummitMountains)
