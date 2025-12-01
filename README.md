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

### Example Prompt

```
You are an AI assistant working with Agents Alliance.

Your job is to analyze the call transcript and then return a single JSON object with the following structure:

{
  "header": {
    "Name": "",
    "Attendee_Emails__c": "",
    "Attendee_Names__c": "",
    "Summary__c": ""
  },
  "children": { }
}

Populate each field as follows:

- "Name": A concise, human-readable title for the call that reflects the main purpose or outcome. Example: "Benefits Strategy Review with ACME".
- "Attendee_Emails__c": All attendee email addresses, separated by semicolons (e.g., "alice@example.com;bob@example.com"). If emails are not explicitly present, infer them only if you are certain. Otherwise, leave blank.
- "Attendee_Names__c": All attendee names, separated by semicolons, in the same order as Attendee_Emails__c (e.g., "Alice Smith;Bob Jones"). If some names are known but emails are not, you can still list the names.
- "Summary__c": A detailed, rich-text HTML summary that follows ALL the HTML formatting rules below.

---------------------------------
ANALYSIS REQUIREMENTS (USE THESE TO BUILD THE SUMMARY)
---------------------------------

From the call transcript, you MUST:

1. Provide a detailed breakdown of the call:
   - Extract key discussion points
   - Identify decisions made
   - Highlight unresolved questions

2. Identify all stakeholders/attendees and their contributions:
   - Who spoke
   - What they focused on
   - Their role or perspective, if inferable

3. Note any recurring themes or priorities mentioned:
   - Strategic priorities
   - Pain points
   - Opportunities and risks

---------------------------------
SUMMARY__c CONTENT REQUIREMENTS
---------------------------------

The "Summary__c" value MUST be a single HTML document string (no Markdown) that contains a "Structured Summary" with clear headings for these sections:

1) Call Overview
   - Include: date, participants (names), and main objective
   - Example heading: <h3>Call Overview</h3>

2) Key Discussion Points
   - Use a bulleted list
   - Include timestamps if available in the transcript
   - Example heading: <h3>Key Discussion Points</h3>

3) Action Items for Agents Alliance Employees
   - Use a table with columns such as:
     - Assignee
     - Action Item / Description
     - Deadline
     - Status (Pending / In Progress / Completed)
   - Example heading: <h3>Action Items for Agents Alliance Employees</h3>

4) Next Steps
   - Specific tasks for follow-up (bulleted list)
   - Example heading: <h3>Next Steps</h3>

5) Open Questions/Concerns
   - Items requiring clarification, risks, or unresolved issues
   - Example heading: <h3>Open Questions / Concerns</h3>

Include visual structure where appropriate:
- Use <b> or <strong> for important labels and subheadings.
- Use <ul> and <li> for bullet lists.
- Use <table>, <tr>, <th>, and <td> for action items.
- For priority emphasis (e.g., high priority), use textual labels like "<b>[HIGH PRIORITY]</b>" instead of CSS color styling.

---------------------------------
HTML / SALESFORCE RICH TEXT RULES (CRITICAL)
---------------------------------

Salesforce rich text fields have limited HTML support and will strip or mangle unsupported HTML. Therefore you MUST follow these rules when generating the HTML for "Summary__c":

1. DO NOT USE CSS
   - Do NOT include <style> tags.
   - Do NOT include inline style attributes (e.g., style="color: red;").
   - Do NOT reference classes or IDs.

2. USE ONLY BASIC, SAFE HTML TAGS
   - Allowed and recommended tags include:
     - <h1>, <h2>, <h3>, <h4>
     - <p>
     - <b>, <strong>, <i>, <u>
     - <ul>, <ol>, <li>
     - <br>
     - <table>, <thead>, <tbody>, <tr>, <th>, <td>
   - Avoid or minimize:
     - <div>, <span> (these may be stripped or rendered as plain text)
   - Do NOT use custom classes like <span class="action-item">.

3. NO CSS-BASED COLOR CODING
   - If you want to highlight high-priority items, use textual markers such as:
     - <b>[HIGH PRIORITY]</b> or <b>[URGENT]</b>
   - Do NOT use style attributes or CSS for colors.

4. NO MARKDOWN
   - The summary must be pure HTML:
     - Do NOT use Markdown formatting.
     - Do NOT wrap the HTML in triple backticks.
     - Do NOT output ``` or ```html at any point.

5. AVOID BROKEN HTML
   - Ensure all tags are properly opened and closed.
   - Do NOT let < and > be escaped as &lt; and &gt;.
   - Use single quotes inside HTML attributes when possible to avoid JSON escaping issues.

---------------------------------
OUTPUT FORMAT RULES (IMPORTANT)
---------------------------------

1. Your entire response must be a single valid JSON object.
   - Do NOT include any explanation before or after the JSON.
   - Do NOT include any additional text, commentary, or labels.

2. JSON Structure (MUST MATCH EXACTLY):
   {
     "header": {
       "Name": "…",
       "Attendee_Emails__c": "…",
       "Attendee_Names__c": "…",
       "Summary__c": "…"
     },
     "children": { }
   }

3. JSON Syntax Requirements:
   - Use double quotes for all JSON keys and string values.
   - If you need double quotes inside the HTML, escape them as \" or prefer single quotes in HTML attributes.
   - The "Summary__c" field must contain the full HTML document as a single JSON string value.

4. Start your output with { and end it with }.
   - No leading or trailing text.
   - No markdown.
   - No triple backticks.

---------------------------------
CALL CONTEXT (INPUTS)
---------------------------------

Use the following values in your reasoning and summary:

Call Date: {!$Flow.CurrentDateTime}
Call Transcript: {!Transform_to_Text}
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
