/**
 * @description Integration tests for JsonToRecordsAction invocable class.
 *              Tests the full flow from invocable entry point through DML.
 *              Includes bulk operation tests for governor limit validation.
 * @author We Summit Mountains
 * @since API 62.0
 */
@IsTest
private class JsonToRecordsActionTest {

    // ═══════════════════════════════════════════════════════════════════════
    // TEST SETUP
    // ═══════════════════════════════════════════════════════════════════════

    @TestSetup
    static void setupTestData() {
        // Create 250 accounts for bulk testing
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 250; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                BillingCity = 'Original City',
                NumberOfEmployees = 10
            ));
        }
        insert accounts;

        // Create some existing contacts for update tests
        List<Contact> contacts = new List<Contact>();
        for (Account acc : [SELECT Id FROM Account LIMIT 50]) {
            contacts.add(new Contact(
                FirstName = 'Original',
                LastName = 'Contact',
                AccountId = acc.Id
            ));
        }
        insert contacts;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POSITIVE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testSingleRecordHeaderUpdate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"header": {"BillingCity": "New City", "NumberOfEmployees": 100}}';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return 1 output');
        System.assertEquals(true, outputs[0].success, 'Should succeed');
        System.assertEquals(true, outputs[0].headerUpdated, 'Header should be marked as updated');

        Account updated = [SELECT BillingCity, NumberOfEmployees FROM Account WHERE Id = :acc.Id];
        System.assertEquals('New City', updated.BillingCity);
        System.assertEquals(100, updated.NumberOfEmployees);
    }

    @IsTest
    static void testChildInsert() {
        Account acc = [SELECT Id FROM Account WHERE Id NOT IN (SELECT AccountId FROM Contact) LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"children": {"Contacts": [' +
            '{"FirstName": "John", "LastName": "Doe", "Email": "john@example.com"},' +
            '{"FirstName": "Jane", "LastName": "Smith", "Email": "jane@example.com"}' +
            ']}}';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success, 'Should succeed');
        System.assertEquals(2, outputs[0].childrenInserted, 'Should insert 2 contacts');

        List<Contact> contacts = [
            SELECT FirstName, LastName, Email
            FROM Contact
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(2, contacts.size(), 'Should have 2 contacts');
    }

    @IsTest
    static void testChildUpdate() {
        Contact existingContact = [SELECT Id, AccountId FROM Contact LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = existingContact.AccountId;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"children": {"Contacts": [' +
            '{"Id": "' + existingContact.Id + '", "FirstName": "Updated", "Title": "Manager"}' +
            ']}}';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success, 'Should succeed');
        System.assertEquals(1, outputs[0].childrenUpdated, 'Should update 1 contact');

        Contact updated = [SELECT FirstName, Title FROM Contact WHERE Id = :existingContact.Id];
        System.assertEquals('Updated', updated.FirstName);
        System.assertEquals('Manager', updated.Title);
    }

    @IsTest
    static void testMixedHeaderAndChildren() {
        Contact existingContact = [SELECT Id, AccountId FROM Contact LIMIT 1];
        Id accountId = existingContact.AccountId;

        String json = '{"header": {"BillingCity": "Updated City", "Website": "https://example.com"},' +
            '"children": {"Contacts": [' +
            '{"Id": "' + existingContact.Id + '", "FirstName": "Modified"},' +
            '{"FirstName": "New", "LastName": "Contact"}' +
            ']}}';

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = accountId;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = json;

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        JsonToRecordsAction.Output output = outputs[0];
        System.assertEquals(true, output.success, 'Should succeed');
        System.assertEquals(true, output.headerUpdated, 'Header should be updated');
        System.assertEquals(1, output.childrenInserted, 'Should insert 1 contact');
        System.assertEquals(1, output.childrenUpdated, 'Should update 1 contact');

        Account updatedAcc = [SELECT BillingCity, Website FROM Account WHERE Id = :accountId];
        System.assertEquals('Updated City', updatedAcc.BillingCity);
        System.assertEquals('https://example.com', updatedAcc.Website);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BULK OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testBulkProcessing200Records() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 200];
        List<JsonToRecordsAction.Input> inputs = new List<JsonToRecordsAction.Input>();

        for (Account acc : accounts) {
            JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
            input.headerId = acc.Id;
            input.sObjectTypeName = 'Account';
            input.jsonPayload = '{"header": {"BillingCity": "Bulk Updated"}}';
            inputs.add(input);
        }

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs = JsonToRecordsAction.execute(inputs);
        Test.stopTest();

        System.assertEquals(200, outputs.size(), 'Should return 200 outputs');

        Integer successCount = 0;
        for (JsonToRecordsAction.Output output : outputs) {
            if (output.success) {
                successCount++;
            }
        }
        System.assertEquals(200, successCount, 'All 200 should succeed');

        List<Account> updated = [SELECT BillingCity FROM Account WHERE BillingCity = 'Bulk Updated'];
        System.assertEquals(200, updated.size(), 'All 200 accounts should be updated');
    }

    @IsTest
    static void testBulkWithChildRecords() {
        // Test bulk processing with child inserts (governor limit validation)
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE Id NOT IN (SELECT AccountId FROM Contact)
            LIMIT 50
        ];
        List<JsonToRecordsAction.Input> inputs = new List<JsonToRecordsAction.Input>();

        for (Account acc : accounts) {
            JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
            input.headerId = acc.Id;
            input.sObjectTypeName = 'Account';
            input.jsonPayload = '{"children": {"Contacts": [' +
                '{"FirstName": "Bulk", "LastName": "Contact"}' +
                ']}}';
            inputs.add(input);
        }

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs = JsonToRecordsAction.execute(inputs);
        Test.stopTest();

        Integer totalInserted = 0;
        for (JsonToRecordsAction.Output output : outputs) {
            if (output.success) {
                totalInserted += output.childrenInserted;
            }
        }
        System.assertEquals(50, totalInserted, 'Should insert 50 contacts total');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NEGATIVE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testMissingHeaderId() {
        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = null;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"header": {"Name": "Test"}}';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(false, outputs[0].success, 'Should fail');
        System.assert(outputs[0].errors[0].contains('Header ID'),
            'Error should mention Header ID');
    }

    @IsTest
    static void testMissingSObjectType() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = '';
        input.jsonPayload = '{"header": {"Name": "Test"}}';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(false, outputs[0].success, 'Should fail');
        System.assert(outputs[0].errors[0].contains('SObject Type'),
            'Error should mention SObject Type');
    }

    @IsTest
    static void testMissingJsonPayload() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(false, outputs[0].success, 'Should fail');
        System.assert(outputs[0].errors[0].contains('JSON Payload'),
            'Error should mention JSON Payload');
    }

    @IsTest
    static void testInvalidJson() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = 'not valid json {{{';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(false, outputs[0].success, 'Should fail');
        System.assert(outputs[0].errors[0].contains('Invalid JSON'),
            'Error should mention Invalid JSON');
    }

    @IsTest
    static void testInvalidSObjectType() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'NonExistentObject__c';
        input.jsonPayload = '{"header": {"Name": "Test"}}';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(false, outputs[0].success, 'Should fail');
        System.assert(outputs[0].errors[0].contains('Invalid SObject type'),
            'Error should mention Invalid SObject type');
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

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success, 'Should succeed');
        System.assertEquals(false, outputs[0].headerUpdated, 'Header should not be updated');
        System.assertEquals(0, outputs[0].childrenInserted, 'No children inserted');
        System.assertEquals('No changes made', outputs[0].message, 'Message should indicate no changes');
    }

    @IsTest
    static void testPartialFailure() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 2];
        List<JsonToRecordsAction.Input> inputs = new List<JsonToRecordsAction.Input>();

        // Valid input
        JsonToRecordsAction.Input valid = new JsonToRecordsAction.Input();
        valid.headerId = accounts[0].Id;
        valid.sObjectTypeName = 'Account';
        valid.jsonPayload = '{"header": {"BillingCity": "Valid"}}';
        inputs.add(valid);

        // Invalid input (missing payload)
        JsonToRecordsAction.Input invalid = new JsonToRecordsAction.Input();
        invalid.headerId = accounts[1].Id;
        invalid.sObjectTypeName = 'Account';
        invalid.jsonPayload = '';
        inputs.add(invalid);

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs = JsonToRecordsAction.execute(inputs);
        Test.stopTest();

        System.assertEquals(2, outputs.size(), 'Should return 2 outputs');
        System.assertEquals(true, outputs[0].success, 'First should succeed');
        System.assertEquals(false, outputs[1].success, 'Second should fail');
    }

    @IsTest
    static void testWarningsReturned() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{"header": {"BillingCity": "Valid", "FakeField__c": "Ignored"}}';

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success, 'Should succeed despite warning');
        System.assert(outputs[0].warnings.size() > 0, 'Should have warnings');
        System.assert(outputs[0].warnings[0].contains('FakeField__c'),
            'Warning should mention the skipped field');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FIELD TYPE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testVariousFieldTypes() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        String json = '{"header": {' +
            '"Name": "Updated Name",' +
            '"NumberOfEmployees": 500,' +
            '"AnnualRevenue": 1000000.50,' +
            '"BillingCity": "Test City",' +
            '"Website": "https://example.com",' +
            '"Description": "A longer text description"' +
            '}}';

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = json;

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success, 'Should succeed');

        Account updated = [
            SELECT Name, NumberOfEmployees, AnnualRevenue, BillingCity, Website, Description
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals('Updated Name', updated.Name);
        System.assertEquals(500, updated.NumberOfEmployees);
        System.assertEquals(1000000.50, updated.AnnualRevenue);
        System.assertEquals('Test City', updated.BillingCity);
        System.assertEquals('https://example.com', updated.Website);
        System.assertEquals('A longer text description', updated.Description);
    }

    @IsTest
    static void testDateFieldInChild() {
        Account acc = [SELECT Id FROM Account WHERE Id NOT IN (SELECT AccountId FROM Contact) LIMIT 1];

        String json = '{"children": {"Contacts": [' +
            '{"FirstName": "Test", "LastName": "Contact", "Birthdate": "1990-05-15"}' +
            ']}}';

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = json;

        Test.startTest();
        List<JsonToRecordsAction.Output> outputs =
            JsonToRecordsAction.execute(new List<JsonToRecordsAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success, 'Should succeed');
        System.assertEquals(1, outputs[0].childrenInserted, 'Should insert 1 contact');

        Contact created = [SELECT Birthdate FROM Contact WHERE AccountId = :acc.Id LIMIT 1];
        System.assertEquals(Date.newInstance(1990, 5, 15), created.Birthdate,
            'Birthdate should be set correctly');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OUTPUT CLASS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testOutputInitialization() {
        JsonToRecordsAction.Output output = new JsonToRecordsAction.Output();

        System.assertEquals(false, output.success, 'Should default to false');
        System.assertEquals(false, output.headerUpdated, 'Should default to false');
        System.assertEquals(0, output.childrenInserted, 'Should default to 0');
        System.assertEquals(0, output.childrenUpdated, 'Should default to 0');
        System.assertNotEquals(null, output.errors, 'Errors list should be initialized');
        System.assertNotEquals(null, output.warnings, 'Warnings list should be initialized');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INPUT CLASS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testInputClass() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        JsonToRecordsAction.Input input = new JsonToRecordsAction.Input();
        input.headerId = acc.Id;
        input.sObjectTypeName = 'Account';
        input.jsonPayload = '{}';

        System.assertEquals(acc.Id, input.headerId);
        System.assertEquals('Account', input.sObjectTypeName);
        System.assertEquals('{}', input.jsonPayload);
    }
}
