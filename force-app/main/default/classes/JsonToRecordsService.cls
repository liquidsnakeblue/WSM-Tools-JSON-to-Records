/**
 * @description Service class handling bulk processing of JSON payloads to Salesforce records.
 *              Designed for bulk safety with batched DML and proper error handling.
 *              Processes all inputs in a single pass to minimize governor limit usage.
 * @author We Summit Mountains
 * @since API 62.0
 */
public with sharing class JsonToRecordsService {

    // ═══════════════════════════════════════════════════════════════════════
    // INNER CLASSES
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Result container for each processed record.
     *              Tracks success, metrics, and any errors or warnings.
     */
    public class ProcessingResult {
        public Boolean success { get; set; }
        public String message { get; set; }
        public Boolean headerUpdated { get; set; }
        public Integer childrenInserted { get; set; }
        public Integer childrenUpdated { get; set; }
        public List<String> errors { get; set; }
        public List<String> warnings { get; set; }

        public ProcessingResult() {
            this.success = true;
            this.headerUpdated = false;
            this.childrenInserted = 0;
            this.childrenUpdated = 0;
            this.errors = new List<String>();
            this.warnings = new List<String>();
        }

        /**
         * @description Add an error and mark the result as failed
         * @param error The error message
         */
        public void addError(String error) {
            this.errors.add(error);
            this.success = false;
        }

        /**
         * @description Add a warning (does not affect success status)
         * @param warning The warning message
         */
        public void addWarning(String warning) {
            this.warnings.add(warning);
        }
    }

    /**
     * @description Internal structure for parsed JSON data
     */
    private class ParsedPayload {
        public Map<String, Object> headerFields;
        public Map<String, List<Map<String, Object>>> childrenByRelationship;

        public ParsedPayload() {
            this.headerFields = new Map<String, Object>();
            this.childrenByRelationship = new Map<String, List<Map<String, Object>>>();
        }
    }

    /**
     * @description Container for collecting child records for batch DML
     */
    private class ChildRecordCollector {
        public List<SObject> toInsert = new List<SObject>();
        public List<SObject> toUpdate = new List<SObject>();
        public Map<Integer, Id> insertIndexToHeaderId = new Map<Integer, Id>();
        public Map<Integer, Id> updateIndexToHeaderId = new Map<Integer, Id>();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC METHODS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Main entry point for bulk processing JSON payloads.
     *              Processes all inputs in a single pass with batched DML.
     * @param inputs List of Input objects containing headerId, sObjectTypeName, and jsonPayload
     * @return Map<Id, ProcessingResult> Results mapped by header record Id
     */
    public Map<Id, ProcessingResult> processRecords(List<JsonToRecordsAction.Input> inputs) {
        Map<Id, ProcessingResult> resultsByHeaderId = new Map<Id, ProcessingResult>();

        // Initialize results for all inputs
        for (JsonToRecordsAction.Input inp : inputs) {
            resultsByHeaderId.put(inp.headerId, new ProcessingResult());
        }

        // Phase 1: Parse all JSON payloads (no DML, no SOQL)
        Map<Id, ParsedPayload> payloadsByHeaderId = parseAllPayloads(inputs, resultsByHeaderId);

        // Phase 2: Collect and validate all header updates
        List<SObject> headersToUpdate = collectHeaderUpdates(inputs, payloadsByHeaderId, resultsByHeaderId);

        // Phase 3: Collect all child records (inserts and updates)
        ChildRecordCollector childCollector = collectChildRecords(inputs, payloadsByHeaderId, resultsByHeaderId);

        // Phase 4: Execute batched DML operations
        executeBulkDml(headersToUpdate, childCollector, resultsByHeaderId);

        // Phase 5: Build final result messages
        for (Id headerId : resultsByHeaderId.keySet()) {
            ProcessingResult result = resultsByHeaderId.get(headerId);
            if (result.success) {
                result.message = buildSuccessMessage(result);
            } else {
                result.message = 'Processing completed with errors';
            }
        }

        return resultsByHeaderId;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 1: JSON PARSING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Parse all JSON payloads without any DML/SOQL
     */
    private Map<Id, ParsedPayload> parseAllPayloads(
        List<JsonToRecordsAction.Input> inputs,
        Map<Id, ProcessingResult> results
    ) {
        Map<Id, ParsedPayload> payloads = new Map<Id, ParsedPayload>();

        for (JsonToRecordsAction.Input inp : inputs) {
            ParsedPayload payload = new ParsedPayload();
            ProcessingResult result = results.get(inp.headerId);

            try {
                Object parsed = JSON.deserializeUntyped(inp.jsonPayload);

                if (!(parsed instanceof Map<String, Object>)) {
                    result.addError('JSON payload must be an object with "header" and/or "children" keys');
                    payloads.put(inp.headerId, payload);
                    continue;
                }

                Map<String, Object> jsonMap = (Map<String, Object>) parsed;

                // Extract header fields
                if (jsonMap.containsKey('header')) {
                    Object headerObj = jsonMap.get('header');
                    if (headerObj instanceof Map<String, Object>) {
                        payload.headerFields = (Map<String, Object>) headerObj;
                    } else if (headerObj != null) {
                        result.addError('"header" must be an object');
                    }
                }

                // Extract children
                if (jsonMap.containsKey('children')) {
                    Object childrenObj = jsonMap.get('children');
                    if (childrenObj instanceof Map<String, Object>) {
                        Map<String, Object> childrenMap = (Map<String, Object>) childrenObj;
                        for (String relName : childrenMap.keySet()) {
                            Object relData = childrenMap.get(relName);
                            if (relData instanceof List<Object>) {
                                List<Map<String, Object>> childList = new List<Map<String, Object>>();
                                for (Object item : (List<Object>) relData) {
                                    if (item instanceof Map<String, Object>) {
                                        childList.add((Map<String, Object>) item);
                                    }
                                }
                                payload.childrenByRelationship.put(relName, childList);
                            }
                        }
                    } else if (childrenObj != null) {
                        result.addError('"children" must be an object keyed by relationship name');
                    }
                }

            } catch (JSONException e) {
                result.addError('Invalid JSON: ' + e.getMessage());
            }

            payloads.put(inp.headerId, payload);
        }

        return payloads;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 2: HEADER COLLECTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Build header SObjects for update with FLS validation
     */
    private List<SObject> collectHeaderUpdates(
        List<JsonToRecordsAction.Input> inputs,
        Map<Id, ParsedPayload> payloads,
        Map<Id, ProcessingResult> results
    ) {
        List<SObject> headersToUpdate = new List<SObject>();

        for (JsonToRecordsAction.Input inp : inputs) {
            ParsedPayload payload = payloads.get(inp.headerId);
            ProcessingResult result = results.get(inp.headerId);

            // Skip if already has errors or no header fields
            if (!result.success || payload.headerFields.isEmpty()) {
                continue;
            }

            try {
                Schema.SObjectType sObjType = SchemaCache.getSObjectType(inp.sObjectTypeName);
                if (sObjType == null) {
                    result.addError('Invalid SObject type: ' + inp.sObjectTypeName);
                    continue;
                }

                // Validate header Id matches expected type
                Schema.SObjectType idType = inp.headerId.getSobjectType();
                if (idType != sObjType) {
                    result.addError('Header ID type mismatch. Expected ' +
                        inp.sObjectTypeName + ' but got ' + idType.getDescribe().getName());
                    continue;
                }

                Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(inp.sObjectTypeName);
                SObject headerRecord = sObjType.newSObject(inp.headerId);
                Boolean hasFieldsToUpdate = false;

                for (String fieldName : payload.headerFields.keySet()) {
                    String fieldNameLower = fieldName.toLowerCase();

                    if (!fieldMap.containsKey(fieldNameLower)) {
                        result.addWarning('Unknown field on header: ' + fieldName + ' - skipped');
                        continue;
                    }

                    Schema.DescribeFieldResult fieldDescribe =
                        fieldMap.get(fieldNameLower).getDescribe();

                    // Check field-level security (Skip & Warn approach)
                    if (!fieldDescribe.isUpdateable()) {
                        result.addWarning('Field "' + fieldName + '" is not updateable - skipped');
                        continue;
                    }

                    try {
                        Object rawValue = payload.headerFields.get(fieldName);
                        Object typedValue = FieldCaster.castValue(rawValue, fieldDescribe);
                        headerRecord.put(fieldDescribe.getName(), typedValue);
                        hasFieldsToUpdate = true;
                    } catch (Exception e) {
                        result.addWarning('Error casting field "' + fieldName + '": ' + e.getMessage() + ' - skipped');
                    }
                }

                if (hasFieldsToUpdate) {
                    headersToUpdate.add(headerRecord);
                    result.headerUpdated = true;
                }

            } catch (Exception e) {
                result.addError('Error processing header: ' + e.getMessage());
            }
        }

        return headersToUpdate;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 3: CHILD RECORD COLLECTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Collect all child records for insert/update with FLS validation
     */
    private ChildRecordCollector collectChildRecords(
        List<JsonToRecordsAction.Input> inputs,
        Map<Id, ParsedPayload> payloads,
        Map<Id, ProcessingResult> results
    ) {
        ChildRecordCollector collector = new ChildRecordCollector();

        for (JsonToRecordsAction.Input inp : inputs) {
            ParsedPayload payload = payloads.get(inp.headerId);
            ProcessingResult result = results.get(inp.headerId);

            if (!result.success || payload.childrenByRelationship.isEmpty()) {
                continue;
            }

            try {
                Schema.SObjectType parentType = SchemaCache.getSObjectType(inp.sObjectTypeName);
                if (parentType == null) {
                    continue; // Already reported as error in header phase
                }

                // Get child relationships
                Map<String, Schema.ChildRelationship> childRelMap =
                    SchemaCache.getChildRelationships(inp.sObjectTypeName);

                for (String relName : payload.childrenByRelationship.keySet()) {
                    String relNameLower = relName.toLowerCase();

                    if (!childRelMap.containsKey(relNameLower)) {
                        result.addWarning('Unknown child relationship: ' + relName + ' - skipped');
                        continue;
                    }

                    Schema.ChildRelationship childRel = childRelMap.get(relNameLower);
                    Schema.SObjectType childType = childRel.getChildSObject();
                    String childTypeName = childType.getDescribe().getName();
                    Schema.SObjectField parentIdField = childRel.getField();
                    String parentIdFieldName = parentIdField.getDescribe().getName();

                    Map<String, Schema.SObjectField> childFieldMap =
                        SchemaCache.getFieldMap(childTypeName);

                    List<Map<String, Object>> childRecords =
                        payload.childrenByRelationship.get(relName);

                    for (Map<String, Object> childData : childRecords) {
                        Boolean isUpdate = childData.containsKey('Id') &&
                            childData.get('Id') != null &&
                            String.isNotBlank(String.valueOf(childData.get('Id')));

                        SObject childRecord;

                        if (isUpdate) {
                            // Update existing child
                            try {
                                Id childId = Id.valueOf(String.valueOf(childData.get('Id')));
                                childRecord = childType.newSObject(childId);
                            } catch (Exception e) {
                                result.addWarning('Invalid child Id in ' + relName + ': ' +
                                    childData.get('Id') + ' - skipped');
                                continue;
                            }
                        } else {
                            // Insert new child - set parent lookup
                            childRecord = childType.newSObject();
                            childRecord.put(parentIdFieldName, inp.headerId);
                        }

                        Boolean hasValidFields = !isUpdate; // Inserts always have parent field

                        for (String fieldName : childData.keySet()) {
                            if (fieldName.equalsIgnoreCase('Id')) {
                                continue;
                            }

                            String fieldNameLower = fieldName.toLowerCase();

                            if (!childFieldMap.containsKey(fieldNameLower)) {
                                result.addWarning('Unknown field on ' + childTypeName +
                                    ': ' + fieldName + ' - skipped');
                                continue;
                            }

                            Schema.DescribeFieldResult fieldDescribe =
                                childFieldMap.get(fieldNameLower).getDescribe();

                            // Check FLS (Skip & Warn approach)
                            if (isUpdate && !fieldDescribe.isUpdateable()) {
                                result.addWarning('Field "' + fieldName + '" on ' +
                                    childTypeName + ' is not updateable - skipped');
                                continue;
                            }
                            if (!isUpdate && !fieldDescribe.isCreateable()) {
                                result.addWarning('Field "' + fieldName + '" on ' +
                                    childTypeName + ' is not createable - skipped');
                                continue;
                            }

                            try {
                                Object rawValue = childData.get(fieldName);
                                Object typedValue = FieldCaster.castValue(rawValue, fieldDescribe);
                                childRecord.put(fieldDescribe.getName(), typedValue);
                                hasValidFields = true;
                            } catch (Exception e) {
                                result.addWarning('Error casting ' + childTypeName + '.' +
                                    fieldName + ': ' + e.getMessage() + ' - skipped');
                            }
                        }

                        if (hasValidFields) {
                            if (isUpdate) {
                                collector.updateIndexToHeaderId.put(
                                    collector.toUpdate.size(), inp.headerId);
                                collector.toUpdate.add(childRecord);
                            } else {
                                collector.insertIndexToHeaderId.put(
                                    collector.toInsert.size(), inp.headerId);
                                collector.toInsert.add(childRecord);
                            }
                        }
                    }
                }

            } catch (Exception e) {
                result.addError('Error processing children: ' + e.getMessage());
            }
        }

        return collector;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 4: BULK DML EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Execute all DML in bulk with partial success support
     */
    private void executeBulkDml(
        List<SObject> headersToUpdate,
        ChildRecordCollector childCollector,
        Map<Id, ProcessingResult> results
    ) {
        // Insert children first (before header update in case of dependencies)
        if (!childCollector.toInsert.isEmpty()) {
            Database.SaveResult[] insertResults =
                Database.insert(childCollector.toInsert, false); // allOrNone = false

            for (Integer i = 0; i < insertResults.size(); i++) {
                Database.SaveResult sr = insertResults[i];
                Id headerId = childCollector.insertIndexToHeaderId.get(i);
                ProcessingResult result = results.get(headerId);

                if (sr.isSuccess()) {
                    result.childrenInserted++;
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        result.addError('Child insert failed: ' + err.getMessage());
                    }
                }
            }
        }

        // Update children
        if (!childCollector.toUpdate.isEmpty()) {
            Database.SaveResult[] updateResults =
                Database.update(childCollector.toUpdate, false);

            for (Integer i = 0; i < updateResults.size(); i++) {
                Database.SaveResult sr = updateResults[i];
                Id headerId = childCollector.updateIndexToHeaderId.get(i);
                ProcessingResult result = results.get(headerId);

                if (sr.isSuccess()) {
                    result.childrenUpdated++;
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        result.addError('Child update failed: ' + err.getMessage());
                    }
                }
            }
        }

        // Update headers last
        if (!headersToUpdate.isEmpty()) {
            Database.SaveResult[] headerResults =
                Database.update(headersToUpdate, false);

            for (Integer i = 0; i < headerResults.size(); i++) {
                Database.SaveResult sr = headerResults[i];
                Id headerId = headersToUpdate[i].Id;
                ProcessingResult result = results.get(headerId);

                if (!sr.isSuccess()) {
                    result.headerUpdated = false;
                    for (Database.Error err : sr.getErrors()) {
                        result.addError('Header update failed: ' + err.getMessage());
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Build human-readable success message
     */
    private String buildSuccessMessage(ProcessingResult result) {
        List<String> parts = new List<String>();

        if (result.headerUpdated) {
            parts.add('Header updated');
        }
        if (result.childrenInserted > 0) {
            parts.add(result.childrenInserted + ' child record(s) inserted');
        }
        if (result.childrenUpdated > 0) {
            parts.add(result.childrenUpdated + ' child record(s) updated');
        }

        String base = parts.isEmpty() ? 'No changes made' : String.join(parts, '; ');

        // Append warning count if any
        if (!result.warnings.isEmpty()) {
            base += ' (' + result.warnings.size() + ' warning(s))';
        }

        return base;
    }
}
