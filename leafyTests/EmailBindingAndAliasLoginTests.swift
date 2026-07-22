import XCTest
@testable import Leafy

final class EmailBindingTests: XCTestCase {
    func testEmailBindingNormalizesEmailAndCode() {
        XCTAssertEqual(
            CommunityEmailBinding.normalizedEmail("  Student.Name+Leafy@Example.COM  "),
            "student.name+leafy@example.com"
        )
        XCTAssertEqual(CommunityEmailBinding.normalizedCode(" 12-34 56 "), "123456")
        XCTAssertEqual(CommunityEmailBinding.normalizedCode("验证码 98 76"), "9876")
    }

    func testEmailBindingValidatesEmailShape() {
        XCTAssertTrue(CommunityEmailBinding.isValidEmail("student@example.com"))
        XCTAssertTrue(CommunityEmailBinding.isValidEmail("student.name+leafy@example.edu.cn"))
        XCTAssertFalse(CommunityEmailBinding.isValidEmail("student"))
        XCTAssertFalse(CommunityEmailBinding.isValidEmail("student@"))
    }

    func testEmailBindingRequiresEightDigitVerificationCode() {
        XCTAssertEqual(CommunityEmailBinding.normalizedCode("12 34-56 78 90"), "12345678")
        XCTAssertTrue(CommunityEmailBinding.isCompleteVerificationCode("12345678"))
        XCTAssertFalse(CommunityEmailBinding.isCompleteVerificationCode("1234567"))
        XCTAssertFalse(CommunityEmailBinding.isCompleteVerificationCode("123456789"))
    }

    func testEmailBindingResendsForSamePendingEmail() {
        XCTAssertTrue(
            CommunityEmailBinding.shouldResendVerification(
                pendingEmail: " Student@Example.com ",
                requestedEmail: "student@example.com"
            )
        )
        XCTAssertFalse(
            CommunityEmailBinding.shouldResendVerification(
                pendingEmail: "old@example.com",
                requestedEmail: "new@example.com"
            )
        )
        XCTAssertFalse(
            CommunityEmailBinding.shouldResendVerification(
                pendingEmail: nil,
                requestedEmail: "new@example.com"
            )
        )
    }

    func testEmailBindingTreatsCurrentNotificationEmailAsAlreadyBound() {
        XCTAssertTrue(
            CommunityEmailBinding.isAlreadyBound(
                boundEmail: " Student@Example.com ",
                requestedEmail: "student@example.com"
            )
        )
        XCTAssertFalse(
            CommunityEmailBinding.isAlreadyBound(
                boundEmail: "old@example.com",
                requestedEmail: "new@example.com"
            )
        )
        XCTAssertFalse(
            CommunityEmailBinding.isAlreadyBound(
                boundEmail: nil,
                requestedEmail: "new@example.com"
            )
        )
    }

}
