/**
 * @description Unit tests for JsonToRecordsService class.
 *              Tests service layer logic directly without going through the invocable wrapper.
 * @author We Summit Mountains
 * @since API 62.0
 */
@IsTest
private class JsonToRecordsServiceTest {

    // ═══════════════════════════════════════════════════════════════════════
    // TEST SETUP
    // ═══════════════════════════════════════════════════════════════════════

    @TestSetup
    static void setupTestData() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 10; i++) {
            accounts.add(new Account(
                Name = 'Service Test Account ' + i,
                BillingCity = 'Original City'
            ));
        }
        insert accounts;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POSITIVE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testProcessRecordsDirectly() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"header": {"BillingCity": "Direct Test"}}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should have one result');
        System.assertEquals(true, results.get(acc.Id).success, 'Should succeed');
        System.assertEquals(true, results.get(acc.Id).headerUpdated, 'Header should be updated');

        Account updated = [SELECT BillingCity FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Direct Test', updated.BillingCity, 'BillingCity should be updated');
    }

    @IsTest
    static void testProcessRecordsWithChildren() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        String json = '{"header": {"BillingCity": "With Children"},' +
            '"children": {"Contacts": [' +
            '{"FirstName": "John", "LastName": "Doe"},' +
            '{"FirstName": "Jane", "LastName": "Smith"}' +
            ']}}';

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = json;

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(true, result.headerUpdated, 'Header should be updated');
        System.assertEquals(2, result.childrenInserted, 'Should insert 2 contacts');

        List<Contact> contacts = [SELECT FirstName, LastName FROM Contact WHERE AccountId = :acc.Id];
        System.assertEquals(2, contacts.size(), 'Should have 2 contacts');
    }

    @IsTest
    static void testChildUpdate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact existingContact = new Contact(
            FirstName = 'Original',
            LastName = 'Contact',
            AccountId = acc.Id
        );
        insert existingContact;

        String json = '{"children": {"Contacts": [' +
            '{"Id": "' + existingContact.Id + '", "FirstName": "Updated"}' +
            ']}}';

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = json;

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(1, result.childrenUpdated, 'Should update 1 contact');

        Contact updated = [SELECT FirstName FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('Updated', updated.FirstName, 'FirstName should be updated');
    }

    @IsTest
    static void testMixedChildInsertAndUpdate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact existingContact = new Contact(
            FirstName = 'Existing',
            LastName = 'Contact',
            AccountId = acc.Id
        );
        insert existingContact;

        String json = '{"children": {"Contacts": [' +
            '{"Id": "' + existingContact.Id + '", "FirstName": "Modified"},' +
            '{"FirstName": "New", "LastName": "Contact"}' +
            ']}}';

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = json;

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(1, result.childrenInserted, 'Should insert 1 contact');
        System.assertEquals(1, result.childrenUpdated, 'Should update 1 contact');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NEGATIVE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testInvalidJson() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{invalid json}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(false, result.success, 'Should fail');
        System.assert(result.errors[0].contains('Invalid JSON'),
            'Error should mention invalid JSON');
    }

    @IsTest
    static void testInvalidSObjectType() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'FakeObject__c';
        input.jsonPayload = '{"header": {"Name": "Test"}}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(false, result.success, 'Should fail');
        System.assert(result.errors[0].contains('Invalid SObject type'),
            'Error should mention invalid SObject type');
    }

    @IsTest
    static void testTypeMismatch() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = acc.Id);
        insert con;

        // Try to use Contact Id with Account type
        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = con.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"header": {"Name": "Test"}}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(con.Id);
        System.assertEquals(false, result.success, 'Should fail due to type mismatch');
        System.assert(result.errors[0].contains('mismatch'),
            'Error should mention type mismatch');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WARNING SCENARIOS (Skip & Warn)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testUnknownFieldWarning() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"header": {"BillingCity": "Valid", "FakeField__c": "Invalid"}}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed (skip unknown field)');
        System.assertEquals(true, result.headerUpdated, 'Header should be updated');
        System.assert(result.warnings.size() > 0, 'Should have warning about unknown field');
        System.assert(result.warnings[0].contains('FakeField__c'),
            'Warning should mention the unknown field');

        Account updated = [SELECT BillingCity FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Valid', updated.BillingCity, 'Valid field should be updated');
    }

    @IsTest
    static void testUnknownRelationshipWarning() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"children": {"FakeRelationship__r": [{"Name": "Test"}]}}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed (skip unknown relationship)');
        System.assert(result.warnings.size() > 0, 'Should have warning');
        System.assert(result.warnings[0].contains('FakeRelationship__r'),
            'Warning should mention the unknown relationship');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testEmptyPayload() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed with no changes');
        System.assertEquals(false, result.headerUpdated, 'Header should not be updated');
        System.assertEquals(0, result.childrenInserted, 'No children inserted');
        System.assertEquals(0, result.childrenUpdated, 'No children updated');
        System.assert(result.message.contains('No changes'), 'Message should indicate no changes');
    }

    @IsTest
    static void testEmptyChildrenArray() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"children": {"Contacts": []}}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(0, result.childrenInserted, 'No children should be inserted');
    }

    @IsTest
    static void testNullHeaderValue() {
        Account acc = [SELECT Id, BillingCity FROM Account LIMIT 1];
        acc.BillingCity = 'Original';
        update acc;

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"header": {"BillingCity": null}}';

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results =
            service.processRecords(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
        System.assertEquals(true, result.success, 'Should succeed');

        Account updated = [SELECT BillingCity FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updated.BillingCity, 'BillingCity should be set to null');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROCESSING RESULT CLASS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testProcessingResultInitialization() {
        JsonToRecordsService.ProcessingResult result = new JsonToRecordsService.ProcessingResult();

        System.assertEquals(true, result.success, 'Should start as success');
        System.assertEquals(false, result.headerUpdated, 'Should start with no header update');
        System.assertEquals(0, result.childrenInserted, 'Should start with 0 inserts');
        System.assertEquals(0, result.childrenUpdated, 'Should start with 0 updates');
        System.assertEquals(0, result.errors.size(), 'Should start with no errors');
        System.assertEquals(0, result.warnings.size(), 'Should start with no warnings');
    }

    @IsTest
    static void testProcessingResultAddError() {
        JsonToRecordsService.ProcessingResult result = new JsonToRecordsService.ProcessingResult();

        result.addError('Test error');

        System.assertEquals(false, result.success, 'Should be marked as failed');
        System.assertEquals(1, result.errors.size(), 'Should have 1 error');
        System.assertEquals('Test error', result.errors[0], 'Error message should match');
    }

    @IsTest
    static void testProcessingResultAddWarning() {
        JsonToRecordsService.ProcessingResult result = new JsonToRecordsService.ProcessingResult();

        result.addWarning('Test warning');

        System.assertEquals(true, result.success, 'Should still be success');
        System.assertEquals(1, result.warnings.size(), 'Should have 1 warning');
        System.assertEquals('Test warning', result.warnings[0], 'Warning message should match');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MULTIPLE INPUTS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testMultipleInputsProcessed() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 5];
        List<JsonToRecordsAction.Input> inputs = new List<JsonToRecordsAction.Input>();

        for (Account acc : accounts) {
            JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
            input.headerId = acc.Id;
            input.sObjectTypeName = 'Account';
            input.jsonPayload = '{"header": {"BillingCity": "Batch Update"}}';
            inputs.add(input);
        }

        JsonToRecordsService service = new JsonToRecordsService();

        Test.startTest();
        Map<Id, JsonToRecordsService.ProcessingResult> results = service.processRecords(inputs);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should have 5 results');

        for (Account acc : accounts) {
            JsonToRecordsService.ProcessingResult result = results.get(acc.Id);
            System.assertEquals(true, result.success, 'Each should succeed');
            System.assertEquals(true, result.headerUpdated, 'Each header should be updated');
        }

        List<Account> updated = [SELECT BillingCity FROM Account WHERE Id IN :accounts];
        for (Account acc : updated) {
            System.assertEquals('Batch Update', acc.BillingCity, 'All should have new city');
        }
    }
}
