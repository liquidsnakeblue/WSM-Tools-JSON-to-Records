/**
 * @description Utility class for casting JSON values to appropriate Apex/Salesforce types.
 *              Handles all standard Salesforce field types including String, Boolean,
 *              Integer, Double, Decimal, Date, DateTime, Time, and Reference (Id).
 * @author We Summit Mountains
 * @since API 62.0
 */
public class FieldCaster {

    /**
     * @description Cast a raw JSON value to the appropriate Apex type based on field describe.
     * @param rawValue The value from JSON (may be String, Number, Boolean, or null)
     * @param fieldDescribe The Schema.DescribeFieldResult for the target field
     * @return Object The properly typed value ready for SObject.put()
     * @throws TypeCastException If the value cannot be converted to the target type
     */
    public static Object castValue(Object rawValue, Schema.DescribeFieldResult fieldDescribe) {
        if (rawValue == null) {
            return null;
        }

        Schema.DisplayType fieldType = fieldDescribe.getType();
        String stringValue = String.valueOf(rawValue);

        // Handle empty strings for non-text types (convert to null)
        if (String.isBlank(stringValue) && !isTextType(fieldType)) {
            return null;
        }

        switch on fieldType {
            // ═══════════════════════════════════════════════════════════════
            // TEXT TYPES - Return as string
            // ═══════════════════════════════════════════════════════════════
            when STRING, TEXTAREA, URL, PHONE, EMAIL, ENCRYPTEDSTRING {
                return stringValue;
            }

            // Picklists are stored as strings
            when PICKLIST, MULTIPICKLIST {
                return stringValue;
            }

            // ═══════════════════════════════════════════════════════════════
            // BOOLEAN
            // ═══════════════════════════════════════════════════════════════
            when BOOLEAN {
                if (rawValue instanceof Boolean) {
                    return rawValue;
                }
                String lowerVal = stringValue.toLowerCase().trim();
                if (lowerVal == 'true' || lowerVal == '1' || lowerVal == 'yes') {
                    return true;
                } else if (lowerVal == 'false' || lowerVal == '0' || lowerVal == 'no') {
                    return false;
                }
                throw new TypeCastException('Cannot convert "' + stringValue + '" to Boolean');
            }

            // ═══════════════════════════════════════════════════════════════
            // NUMERIC TYPES
            // ═══════════════════════════════════════════════════════════════
            when INTEGER {
                if (rawValue instanceof Integer) {
                    return rawValue;
                }
                if (rawValue instanceof Decimal) {
                    return ((Decimal) rawValue).intValue();
                }
                if (rawValue instanceof Double) {
                    return Integer.valueOf(((Double) rawValue).intValue());
                }
                if (rawValue instanceof Long) {
                    return Integer.valueOf(((Long) rawValue).intValue());
                }
                return Integer.valueOf(stringValue);
            }

            when DOUBLE {
                if (rawValue instanceof Double) {
                    return rawValue;
                }
                if (rawValue instanceof Decimal) {
                    return ((Decimal) rawValue).doubleValue();
                }
                if (rawValue instanceof Integer) {
                    return Double.valueOf((Integer) rawValue);
                }
                if (rawValue instanceof Long) {
                    return Double.valueOf((Long) rawValue);
                }
                return Double.valueOf(stringValue);
            }

            when CURRENCY, PERCENT {
                if (rawValue instanceof Decimal) {
                    return rawValue;
                }
                if (rawValue instanceof Double) {
                    return Decimal.valueOf((Double) rawValue);
                }
                if (rawValue instanceof Integer) {
                    return Decimal.valueOf((Integer) rawValue);
                }
                if (rawValue instanceof Long) {
                    return Decimal.valueOf((Long) rawValue);
                }
                return Decimal.valueOf(stringValue);
            }

            when LONG {
                if (rawValue instanceof Long) {
                    return rawValue;
                }
                if (rawValue instanceof Integer) {
                    return (Long) rawValue;
                }
                if (rawValue instanceof Decimal) {
                    return ((Decimal) rawValue).longValue();
                }
                if (rawValue instanceof Double) {
                    return ((Double) rawValue).longValue();
                }
                return Long.valueOf(stringValue);
            }

            // ═══════════════════════════════════════════════════════════════
            // DATE/TIME TYPES
            // ═══════════════════════════════════════════════════════════════
            when DATE {
                if (rawValue instanceof Date) {
                    return rawValue;
                }
                // Support ISO format: YYYY-MM-DD
                return Date.valueOf(stringValue.trim());
            }

            when DATETIME {
                if (rawValue instanceof Datetime) {
                    return rawValue;
                }
                // Support multiple ISO formats:
                // - YYYY-MM-DDTHH:MM:SS.sssZ
                // - YYYY-MM-DD HH:MM:SS
                // - YYYY-MM-DDTHH:MM:SSZ
                String normalized = stringValue.trim()
                    .replace('T', ' ')
                    .replace('Z', '');
                // Remove milliseconds if present
                if (normalized.contains('.')) {
                    normalized = normalized.substringBefore('.');
                }
                return Datetime.valueOf(normalized);
            }

            when TIME {
                if (rawValue instanceof Time) {
                    return rawValue;
                }
                // Parse HH:MM:SS or HH:MM:SS.sss
                return parseTime(stringValue.trim());
            }

            // ═══════════════════════════════════════════════════════════════
            // ID / REFERENCE
            // ═══════════════════════════════════════════════════════════════
            when ID, REFERENCE {
                if (rawValue instanceof Id) {
                    return rawValue;
                }
                String trimmed = stringValue.trim();
                if (String.isBlank(trimmed)) {
                    return null;
                }
                return Id.valueOf(trimmed);
            }

            // ═══════════════════════════════════════════════════════════════
            // BINARY / BLOB
            // ═══════════════════════════════════════════════════════════════
            when BASE64 {
                return EncodingUtil.base64Decode(stringValue);
            }

            // ═══════════════════════════════════════════════════════════════
            // UNSUPPORTED TYPES
            // ═══════════════════════════════════════════════════════════════
            when else {
                // LOCATION, ADDRESS, ANYTYPE, COMPLEXVALUE, DATACATEGORYGROUPREFERENCE
                // These typically cannot be set via simple JSON
                return null;
            }
        }
    }

    /**
     * @description Check if a field type is text-based (can accept empty string)
     * @param fieldType The Schema.DisplayType to check
     * @return Boolean True if text-based type
     */
    private static Boolean isTextType(Schema.DisplayType fieldType) {
        return fieldType == Schema.DisplayType.STRING ||
               fieldType == Schema.DisplayType.TEXTAREA ||
               fieldType == Schema.DisplayType.URL ||
               fieldType == Schema.DisplayType.PHONE ||
               fieldType == Schema.DisplayType.EMAIL ||
               fieldType == Schema.DisplayType.PICKLIST ||
               fieldType == Schema.DisplayType.MULTIPICKLIST ||
               fieldType == Schema.DisplayType.ENCRYPTEDSTRING;
    }

    /**
     * @description Parse a time string in HH:MM:SS or HH:MM:SS.sss format
     * @param timeStr The time string to parse
     * @return Time The parsed Time value
     * @throws TypeCastException If the format is invalid
     */
    private static Time parseTime(String timeStr) {
        if (String.isBlank(timeStr)) {
            return null;
        }

        List<String> parts = timeStr.split(':');
        if (parts.size() < 2) {
            throw new TypeCastException('Invalid time format: ' + timeStr + '. Expected HH:MM:SS');
        }

        Integer hours = Integer.valueOf(parts[0]);
        Integer minutes = Integer.valueOf(parts[1]);
        Integer seconds = 0;
        Integer milliseconds = 0;

        if (parts.size() >= 3) {
            String secPart = parts[2];
            if (secPart.contains('.')) {
                List<String> secSplit = secPart.split('\\.');
                seconds = Integer.valueOf(secSplit[0]);
                if (secSplit.size() > 1) {
                    String msPart = secSplit[1];
                    // Normalize to 3 digits (milliseconds)
                    msPart = msPart.rightPad(3, '0').substring(0, 3);
                    milliseconds = Integer.valueOf(msPart);
                }
            } else {
                seconds = Integer.valueOf(secPart);
            }
        }

        return Time.newInstance(hours, minutes, seconds, milliseconds);
    }

    /**
     * @description Custom exception for type casting errors
     */
    public class TypeCastException extends Exception {}
}
