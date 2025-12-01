/**
 * @description Thread-safe singleton cache for Schema describe results.
 *              Minimizes describe calls within a transaction to conserve CPU time
 *              and avoid repeated expensive operations.
 * @author We Summit Mountains
 * @since API 62.0
 */
public class SchemaCache {

    // ═══════════════════════════════════════════════════════════════════════
    // STATIC CACHES - Persist for duration of transaction
    // ═══════════════════════════════════════════════════════════════════════

    private static Map<String, Schema.SObjectType> sObjectTypeCache =
        new Map<String, Schema.SObjectType>();

    private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache =
        new Map<String, Map<String, Schema.SObjectField>>();

    private static Map<String, Map<String, Schema.ChildRelationship>> childRelCache =
        new Map<String, Map<String, Schema.ChildRelationship>>();

    // Global describe - lazy loaded once per transaction
    private static Map<String, Schema.SObjectType> globalDescribe;

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC METHODS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Get SObjectType by API name (case-insensitive)
     * @param sObjectTypeName The API name of the SObject (e.g., 'Account', 'Custom__c')
     * @return Schema.SObjectType The SObjectType, or null if not found
     */
    public static Schema.SObjectType getSObjectType(String sObjectTypeName) {
        if (String.isBlank(sObjectTypeName)) {
            return null;
        }

        String key = sObjectTypeName.toLowerCase();

        if (!sObjectTypeCache.containsKey(key)) {
            if (globalDescribe == null) {
                globalDescribe = Schema.getGlobalDescribe();
            }
            // Try exact match first, then case-insensitive
            Schema.SObjectType sObjType = globalDescribe.get(sObjectTypeName);
            if (sObjType == null) {
                // Iterate for case-insensitive match
                for (String typeName : globalDescribe.keySet()) {
                    if (typeName.equalsIgnoreCase(sObjectTypeName)) {
                        sObjType = globalDescribe.get(typeName);
                        break;
                    }
                }
            }
            sObjectTypeCache.put(key, sObjType);
        }

        return sObjectTypeCache.get(key);
    }

    /**
     * @description Get field map for an SObject with lowercase field names as keys.
     *              This allows case-insensitive field lookups.
     * @param sObjectTypeName The API name of the SObject
     * @return Map<String, Schema.SObjectField> Map of lowercase field names to SObjectField
     */
    public static Map<String, Schema.SObjectField> getFieldMap(String sObjectTypeName) {
        if (String.isBlank(sObjectTypeName)) {
            return new Map<String, Schema.SObjectField>();
        }

        String key = sObjectTypeName.toLowerCase();

        if (!fieldMapCache.containsKey(key)) {
            Schema.SObjectType sObjType = getSObjectType(sObjectTypeName);
            if (sObjType == null) {
                fieldMapCache.put(key, new Map<String, Schema.SObjectField>());
            } else {
                Map<String, Schema.SObjectField> originalMap = sObjType.getDescribe().fields.getMap();
                Map<String, Schema.SObjectField> lowercaseMap = new Map<String, Schema.SObjectField>();

                for (String fieldName : originalMap.keySet()) {
                    lowercaseMap.put(fieldName.toLowerCase(), originalMap.get(fieldName));
                }

                fieldMapCache.put(key, lowercaseMap);
            }
        }

        return fieldMapCache.get(key);
    }

    /**
     * @description Get child relationships for an SObject with lowercase relationship names as keys.
     *              This allows case-insensitive relationship lookups.
     * @param sObjectTypeName The API name of the parent SObject
     * @return Map<String, Schema.ChildRelationship> Map of lowercase relationship names to ChildRelationship
     */
    public static Map<String, Schema.ChildRelationship> getChildRelationships(String sObjectTypeName) {
        if (String.isBlank(sObjectTypeName)) {
            return new Map<String, Schema.ChildRelationship>();
        }

        String key = sObjectTypeName.toLowerCase();

        if (!childRelCache.containsKey(key)) {
            Schema.SObjectType sObjType = getSObjectType(sObjectTypeName);
            if (sObjType == null) {
                childRelCache.put(key, new Map<String, Schema.ChildRelationship>());
            } else {
                Map<String, Schema.ChildRelationship> relMap =
                    new Map<String, Schema.ChildRelationship>();

                for (Schema.ChildRelationship rel : sObjType.getDescribe().getChildRelationships()) {
                    String relName = rel.getRelationshipName();
                    if (String.isNotBlank(relName)) {
                        relMap.put(relName.toLowerCase(), rel);
                    }
                }

                childRelCache.put(key, relMap);
            }
        }

        return childRelCache.get(key);
    }

    /**
     * @description Get the describe result for an SObject type
     * @param sObjectTypeName The API name of the SObject
     * @return Schema.DescribeSObjectResult The describe result, or null if type not found
     */
    public static Schema.DescribeSObjectResult getDescribe(String sObjectTypeName) {
        Schema.SObjectType sObjType = getSObjectType(sObjectTypeName);
        return sObjType != null ? sObjType.getDescribe() : null;
    }

    /**
     * @description Clear all caches. Useful for testing or when processing
     *              different orgs within the same transaction (rare).
     */
    @TestVisible
    private static void clearCache() {
        sObjectTypeCache.clear();
        fieldMapCache.clear();
        childRelCache.clear();
        globalDescribe = null;
    }
}
