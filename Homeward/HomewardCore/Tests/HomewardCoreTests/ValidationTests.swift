import XCTest
@testable import HomewardCore

final class ValidationTests: XCTestCase {
    func testNUBANCheckDigit() {
        XCTAssertEqual(PayoutValidator.nubanCheckDigit(bankCode: "058", serial: "012345678"), 5)
        XCTAssertEqual(PayoutValidator.makeNUBAN(bankCode: "058", serial: "012345678"), "0123456785")
        XCTAssertNil(PayoutValidator.validateNUBAN(bankCode: "058", accountNumber: "0123456785"))
        XCTAssertNil(PayoutValidator.validateNUBAN(bankCode: "058", accountNumber: "012 345 6785"))
    }

    func testNUBANCatchesSingleDigitTypos() {
        let valid = PayoutValidator.makeNUBAN(bankCode: "044", serial: "690000123")!
        var caught = 0
        var total = 0
        for position in 0..<10 {
            var digits = Array(valid)
            let original = digits[position]
            for replacement in "0123456789" where replacement != original {
                digits[position] = replacement
                total += 1
                if PayoutValidator.validateNUBAN(bankCode: "044", accountNumber: String(digits)) == .checksumFailed { caught += 1 }
            }
        }
        XCTAssertEqual(caught, total, "every single-digit substitution should be caught")
    }

    func testNUBANWrongBankIsCaught() {
        let gtbAccount = PayoutValidator.makeNUBAN(bankCode: "058", serial: "012345678")!
        XCTAssertEqual(PayoutValidator.validateNUBAN(bankCode: "057", accountNumber: gtbAccount), .checksumFailed)
    }

    func testNUBANBasics() {
        XCTAssertEqual(PayoutValidator.validateNUBAN(bankCode: "999", accountNumber: "0123456785"), .unknownBank)
        XCTAssertEqual(PayoutValidator.validateNUBAN(bankCode: "058", accountNumber: ""), .empty(field: "account number"))
        XCTAssertEqual(PayoutValidator.validateNUBAN(bankCode: "058", accountNumber: "12345"), .wrongLength(field: "account number", expected: "10 digits"))
        XCTAssertEqual(PayoutValidator.validateNUBAN(bankCode: "058", accountNumber: "01234X6785"), .notNumeric(field: "account number"))
        // Fintech banks have no public check digit, so any 10 digits pass.
        XCTAssertNil(PayoutValidator.validateNUBAN(bankCode: "50515", accountNumber: "8123456789"))
    }

    func testGhanaMobileMoney() {
        XCTAssertEqual(PayoutValidator.normalizeGhanaPhone("+233 24 123 4567"), "0241234567")
        XCTAssertEqual(PayoutValidator.normalizeGhanaPhone("241234567"), "0241234567")
        XCTAssertEqual(PayoutValidator.ghanaNetwork(for: "0201234567"), .telecel)
        XCTAssertNil(PayoutValidator.validateGhanaMobile(network: .mtn, phone: "024 123 4567"))
        XCTAssertEqual(PayoutValidator.validateGhanaMobile(network: .mtn, phone: "0201234567"),
                       .wrongNetwork(expected: .mtn, detected: .telecel))
        XCTAssertEqual(PayoutValidator.validateGhanaMobile(network: .mtn, phone: "12345"),
                       .invalidFormat(field: "phone number", example: "024 123 4567"))
    }

    func testKenyaMpesa() {
        XCTAssertEqual(PayoutValidator.normalizeKenyaPhone("0712 345 678"), "254712345678")
        XCTAssertEqual(PayoutValidator.normalizeKenyaPhone("+254 110 123456"), "254110123456")
        XCTAssertNil(PayoutValidator.normalizeKenyaPhone("0812345678"))
        XCTAssertNil(PayoutValidator.validateKenyaMpesa(phone: "0712345678"))
        XCTAssertNotNil(PayoutValidator.validateKenyaMpesa(phone: "071234"))
    }

    func testIndia() {
        XCTAssertTrue(PayoutValidator.isValidIFSC("HDFC0001234"))
        XCTAssertTrue(PayoutValidator.isValidIFSC("sbin0005943"))
        XCTAssertFalse(PayoutValidator.isValidIFSC("HDFC1001234"))
        XCTAssertFalse(PayoutValidator.isValidIFSC("HDF00001234"))
        XCTAssertNil(PayoutValidator.validateIndiaBank(ifsc: "HDFC0001234", accountNumber: "50100123456789"))
        XCTAssertEqual(PayoutValidator.validateIndiaBank(ifsc: "HDFC0001234", accountNumber: "1234"),
                       .wrongLength(field: "account number", expected: "9–18 digits"))
        XCTAssertNil(PayoutValidator.validateUPI("priya.sharma@okhdfc"))
        XCTAssertNotNil(PayoutValidator.validateUPI("priya.sharma"))
        XCTAssertNotNil(PayoutValidator.validateUPI("p@ok1"))
    }

    func testNameMatcher() {
        XCTAssertEqual(NameMatcher.compare(entered: "Folake Adeyemi", verified: "ADEYEMI FOLAKE ABIOLA"), .match)
        XCTAssertEqual(NameMatcher.compare(entered: "Chidi Okafor", verified: "OKAFOR, CHIDI"), .match)
        XCTAssertEqual(NameMatcher.compare(entered: "Adébáyọ̀ Okafor", verified: "ADEBAYO OKAFOR"), .match)
        XCTAssertEqual(NameMatcher.compare(entered: "Ade Okafor", verified: "ADEBAYO OKAFOR"), .partial)
        XCTAssertEqual(NameMatcher.compare(entered: "Ngozi", verified: "NGOZI OKAFOR"), .partial)
        XCTAssertEqual(NameMatcher.compare(entered: "Chidi Okafor", verified: "MUSA IBRAHIM"), .mismatch)
        XCTAssertEqual(NameMatcher.compare(entered: "", verified: "MUSA IBRAHIM"), .mismatch)
    }

    func testDirectoryResolver() async throws {
        let details = PayoutDetails.kenyaMpesa(phone: "0712345678")
        let resolver = DirectoryNameResolver(directory: [details: "WANJIRU KAMAU"])
        let name = try await resolver.resolveName(for: details)
        XCTAssertEqual(name, "WANJIRU KAMAU")
        do {
            _ = try await resolver.resolveName(for: .kenyaMpesa(phone: "0799999999"))
            XCTFail("expected not found")
        } catch {
            XCTAssertEqual(error as? AccountLookupError, .accountNotFound)
        }
    }
}
