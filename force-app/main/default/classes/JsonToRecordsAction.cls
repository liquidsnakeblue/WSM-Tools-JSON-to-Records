/**
 * @description Invocable action for Flow/Process Builder to apply JSON payloads
 *              to header (parent) and child records in a bulk-safe manner.
 *
 *              This class serves as the thin entry point for the invocable action,
 *              delegating all business logic to JsonToRecordsService.
 *
 * @author We Summit Mountains
 * @since API 62.0
 * @see JsonToRecordsService
 * @see FieldCaster
 * @see SchemaCache
 */
public with sharing class JsonToRecordsAction {

    // ═══════════════════════════════════════════════════════════════════════
    // INPUT/OUTPUT CLASSES
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Input wrapper for the invocable method.
     *              Contains all parameters needed to process a single record.
     */
    public class Input {
        @InvocableVariable(
            label='Header Record Id'
            description='The Id of the parent record to update'
            required=true
        )
        public Id headerId;

        @InvocableVariable(
            label='SObject Type API Name'
            description='API name of the parent object (e.g., "Opportunity", "Account")'
            required=true
        )
        public String sObjectTypeName;

        @InvocableVariable(
            label='JSON Payload'
            description='JSON with "header" (fields to update) and/or "children" (child records by relationship name)'
            required=true
        )
        public String jsonPayload;
    }

    /**
     * @description Output wrapper for the invocable method.
     *              Contains results and metrics for Flow decision logic.
     */
    public class Output {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Header Updated')
        public Boolean headerUpdated;

        @InvocableVariable(label='Children Inserted Count')
        public Integer childrenInserted;

        @InvocableVariable(label='Children Updated Count')
        public Integer childrenUpdated;

        @InvocableVariable(label='Error Messages')
        public List<String> errors;

        @InvocableVariable(label='Warning Messages')
        public List<String> warnings;

        /**
         * @description Initialize with default values
         */
        public Output() {
            this.success = false;
            this.headerUpdated = false;
            this.childrenInserted = 0;
            this.childrenUpdated = 0;
            this.errors = new List<String>();
            this.warnings = new List<String>();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVOCABLE METHOD
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Main invocable method - processes all inputs in bulk.
     *              Called by Flow Builder, Process Builder, or Apex.
     *
     * @param inputs List of Input objects to process
     * @return List<Output> Results in the same order as inputs
     *
     * @example
     * // In Flow: Use "Apply JSON to Header & Children" action
     * // Set headerId, sObjectTypeName, and jsonPayload
     *
     * // JSON format:
     * // {
     * //   "header": { "StageName": "Closed Won", "CloseDate": "2025-12-31" },
     * //   "children": {
     * //     "OpportunityLineItems": [
     * //       { "Id": "00kXXX...", "Quantity": 10 },
     * //       { "Quantity": 5, "UnitPrice": 100, "PricebookEntryId": "01uXXX..." }
     * //     ]
     * //   }
     * // }
     */
    @InvocableMethod(
        label='Apply JSON to Header & Children'
        description='Updates a parent record and its child records using a JSON payload. Supports bulk processing with partial success.'
        category='Record Operations'
    )
    public static List<Output> execute(List<Input> inputs) {
        List<Output> outputs = new List<Output>();

        // Pre-validate all inputs before processing
        List<Input> validInputs = new List<Input>();
        Map<Integer, Output> outputByIndex = new Map<Integer, Output>();

        for (Integer i = 0; i < inputs.size(); i++) {
            Output output = new Output();
            Input inp = inputs[i];

            List<String> validationErrors = validateInput(inp);

            if (!validationErrors.isEmpty()) {
                output.success = false;
                output.errors = validationErrors;
                output.message = 'Validation failed';
            } else {
                validInputs.add(inp);
            }

            outputByIndex.put(i, output);
        }

        // Process valid inputs through service
        if (!validInputs.isEmpty()) {
            JsonToRecordsService service = new JsonToRecordsService();
            Map<Id, JsonToRecordsService.ProcessingResult> results =
                service.processRecords(validInputs);

            // Map results back to outputs
            for (Integer i = 0; i < inputs.size(); i++) {
                Input inp = inputs[i];
                Output output = outputByIndex.get(i);

                // Only map if this was a valid input that was processed
                if (inp.headerId != null && results.containsKey(inp.headerId)) {
                    JsonToRecordsService.ProcessingResult result = results.get(inp.headerId);
                    output.success = result.success;
                    output.message = result.message;
                    output.headerUpdated = result.headerUpdated;
                    output.childrenInserted = result.childrenInserted;
                    output.childrenUpdated = result.childrenUpdated;
                    output.errors = result.errors;
                    output.warnings = result.warnings;
                }
            }
        }

        // Build ordered output list
        for (Integer i = 0; i < inputs.size(); i++) {
            outputs.add(outputByIndex.get(i));
        }

        return outputs;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Validate input parameters before processing
     * @param inp The input to validate
     * @return List<String> List of validation error messages (empty if valid)
     */
    private static List<String> validateInput(Input inp) {
        List<String> errors = new List<String>();

        if (inp == null) {
            errors.add('Input cannot be null');
            return errors;
        }

        if (inp.headerId == null) {
            errors.add('Header ID is required');
        }

        if (String.isBlank(inp.sObjectTypeName)) {
            errors.add('SObject Type Name is required');
        }

        if (String.isBlank(inp.jsonPayload)) {
            errors.add('JSON Payload is required');
        }

        return errors;
    }
}
