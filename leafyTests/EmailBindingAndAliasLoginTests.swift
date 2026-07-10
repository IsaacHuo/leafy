import Supabase
import XCTest
@testable import Leafy

final class EmailBindingAndAliasLoginTests: XCTestCase {
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

    func testLoginIdentifierDetectsEmailAliasCandidates() {
        XCTAssertTrue(CampusEmailAliasLoginService.isEmailIdentifier(" student@example.com "))
        XCTAssertTrue(CampusEmailAliasLoginService.isEmailIdentifier("student@"))
        XCTAssertFalse(CampusEmailAliasLoginService.isEmailIdentifier("20260001"))
        XCTAssertFalse(CampusEmailAliasLoginService.isEmailIdentifier(" 20260001 "))
    }

    func testAliasLoginMapsNotFoundEnvelope() {
        let payload = Data("""
        {
          "error": "没有找到这个邮箱对应的北林学号；请先用学号登录并绑定邮箱。",
          "errorEnvelope": {
            "code": "not_found",
            "message": "没有找到这个邮箱对应的北林学号；请先用学号登录并绑定邮箱。",
            "retryable": false
          }
        }
        """.utf8)

        let error = CampusEmailAliasLoginService.mapFunctionsErrorForTesting(
            .httpError(code: 404, data: payload)
        )

        XCTAssertEqual(error.localizedDescription, CampusEmailAliasLoginError.notBound.localizedDescription)
    }

    func testAliasLoginMapsInvalidEmailEnvelope() {
        let payload = Data("""
        {
          "errorEnvelope": {
            "code": "bad_request",
            "message": "请输入有效的邮箱地址。",
            "retryable": false
          }
        }
        """.utf8)

        let error = CampusEmailAliasLoginService.mapFunctionsErrorForTesting(
            .httpError(code: 400, data: payload)
        )

        XCTAssertEqual(error.localizedDescription, CampusEmailAliasLoginError.invalidEmail.localizedDescription)
    }

    func testAliasLoginMapsBackendUnavailable() {
        let error = CampusEmailAliasLoginService.mapFunctionsErrorForTesting(.relayError)

        XCTAssertEqual(
            error.localizedDescription,
            CampusEmailAliasLoginError.backendUnavailable("邮箱别名服务暂时不可用，请稍后再试。").localizedDescription
        )
    }
}
