import Foundation
import XCTest
#if canImport(GupKit)
@testable import GupKit
#else
@testable import GupWorks3
#endif

/// a233: the push notifications' categories, what their buttons send, taking delivered ones back, the environment and
/// which token answers. The payloads are the ones tools/gw3_push.py makes (test_gw3_push.PayloadTest).
final class PushTests: XCTestCase {
    // as gw3_push.alert_payload makes them, parsed the way iOS hands them over (JSONSerialization)
    func info(_ json: String) -> [AnyHashable: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [AnyHashable: Any]
    }

    let ask = """
    {"aps": {"alert": {"title": "Home server", "subtitle": "a14 · Memory limits", "body": "Add swap?"},
             "sound": "default", "category": "gw3.ask.rec.other", "thread-id": "p1"},
     "needs": "ask:p1:q3", "gw3": {"kind": "ask", "rec": 0, "chat": "main-1"}}
    """
    let permission = """
    {"aps": {"category": "gw3.permission"}, "needs": "chat:c1:abc", "gw3": {"kind": "permission", "allow": 0, "deny": 2}}
    """
    let memory = """
    {"aps": {"category": "gw3.memory"}, "needs": "memory:m7", "gw3": {"kind": "memory", "sleep": 0}}
    """

    func testCategoriesMatchThePCs() {
        // every category gw3_push.category can name, with its buttons in order
        XCTAssertEqual(PushCategory.all.map(\.id), ["gw3.ask.rec.other", "gw3.ask.rec", "gw3.ask.other", "gw3.ask",
                                                    "gw3.permission", "gw3.memory", "gw3.open"])
        XCTAssertEqual(PushCategory.buttons("gw3.ask.rec.other").map(\.title), ["Send recommended", "Something else…", "Dismiss"])
        XCTAssertEqual(PushCategory.buttons("gw3.permission").map(\.title), ["Allow once", "Deny"])
        XCTAssertEqual(PushCategory.buttons("gw3.memory").map(\.title), ["Sleep idle chats", "Dismiss"])
        XCTAssertEqual(PushCategory.buttons("gw3.open"), [])
        XCTAssertEqual(PushCategory.buttons("nonsense"), [])
        XCTAssertTrue(PushCategory.other.text)
        XCTAssertTrue(PushCategory.deny.destructive && PushCategory.dismiss.destructive)
        XCTAssertFalse(PushCategory.allow.destructive)
        // ids unique within a category
        for c in PushCategory.all { XCTAssertEqual(Set(c.buttons.map(\.id)).count, c.buttons.count) }
    }

    func testAskButtons() {
        let i = info(ask)
        XCTAssertEqual(PushAction.from(action: "gw3.rec", info: i), .answer(key: "ask:p1:q3", option: 0))
        XCTAssertEqual(PushAction.from(action: "gw3.dismiss", info: i), .dismiss(key: "ask:p1:q3"))
        XCTAssertEqual(PushAction.from(action: "gw3.other", info: i, text: "  Teal, like the logo \n"),
                       .text(key: "ask:p1:q3", words: "Teal, like the logo"))
        XCTAssertNil(PushAction.from(action: "gw3.other", info: i, text: "   "))  // dictation heard nothing
        XCTAssertNil(PushAction.from(action: "gw3.allow", info: i))  // not this push's button
        XCTAssertNil(PushAction.from(action: "com.apple.UNNotificationDefaultActionIdentifier", info: i))  // a tap opens
    }

    func testPermissionAndMemoryButtons() {
        XCTAssertEqual(PushAction.from(action: "gw3.allow", info: info(permission)), .answer(key: "chat:c1:abc", option: 0))
        XCTAssertEqual(PushAction.from(action: "gw3.deny", info: info(permission)), .answer(key: "chat:c1:abc", option: 2))
        XCTAssertNil(PushAction.from(action: "gw3.rec", info: info(permission)))
        XCTAssertEqual(PushAction.from(action: "gw3.sleep", info: info(memory)), .answer(key: "memory:m7", option: 0))
        XCTAssertEqual(PushAction.from(action: "gw3.dismiss", info: info(memory)), .dismiss(key: "memory:m7"))
        XCTAssertNil(PushAction.from(action: "gw3.rec", info: ["gw3": ["rec": 0]]))  // no item: not ours
    }

    func testWhatEachButtonSends() {
        XCTAssertEqual(PushAction.answer(key: "k", option: 2).path, "/v1/needs/answer")
        XCTAssertEqual(PushAction.answer(key: "k", option: 2).body, NeedsAction(key: "k", option: 2))
        XCTAssertEqual(PushAction.text(key: "k", words: "w").body, NeedsAction(key: "k", text: "w"))
        XCTAssertEqual(PushAction.dismiss(key: "k").path, "/v1/needs/dismiss")
        XCTAssertEqual(PushAction.dismiss(key: "k").body, NeedsAction(key: "k"))
        let json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(PushAction.answer(key: "k", option: 1).body))
        XCTAssertEqual(json as? NSDictionary, ["key": "k", "option": 1] as NSDictionary)
    }

    func testTakingBack() {
        let delivered: [(id: String, key: String?)] = [("n1", "ask:p:q1"), ("n2", "ask:p:q2"), ("studio-1", nil), ("n3", "memory:m1")]
        XCTAssertEqual(PushPayload.toRemove(delivered, gone: ["ask:p:q1"], live: nil), ["n1"])
        XCTAssertEqual(PushPayload.toRemove(delivered, gone: ["ask:p:q1"], live: ["ask:p:q2"]), ["n1", "n3"])
        XCTAssertEqual(PushPayload.toRemove(delivered, live: []), ["n1", "n2", "n3"])  // a Studio one stays
        let r = PushPayload.removal(info(#"{"aps": {"content-available": 1}, "gone": ["ask:p:q1"], "live": ["ask:p:q2"]}"#))
        XCTAssertEqual(r?.gone, ["ask:p:q1"])
        XCTAssertEqual(r?.live, ["ask:p:q2"])
        XCTAssertNil(PushPayload.removal(info(ask)))
        XCTAssertEqual(PushPayload.key(info(ask)), "ask:p1:q3")
        XCTAssertNil(PushPayload.key(["studioProject": "x"]))
    }

    func testEnvironmentFromTheProfile() {
        XCTAssertEqual(PushEnvironment.of(profile: nil), "production")  // TestFlight, App Store
        let dev = Data("junk<plist><dict><key>Entitlements</key><dict><key>aps-environment</key>\n\t\t<string>development</string>".utf8)
        XCTAssertEqual(PushEnvironment.of(profile: dev), "development")
        let prod = Data("<key>aps-environment</key><string>production</string>".utf8)
        XCTAssertEqual(PushEnvironment.of(profile: prod), "production")
        XCTAssertEqual(PushEnvironment.of(profile: Data("<key>get-task-allow</key><true/>".utf8)), "production")
    }

    func testTokenAndTeam() {
        XCTAssertEqual(PushToken.hex(Data([0x00, 0xab, 0x10, 0xff])), "00ab10ff")
        XCTAssertEqual(PushToken.team("ABCDE12345"), "ABCDE12345")
        XCTAssertEqual(PushToken.team("ABCDE12345."), "ABCDE12345")  // as AppIdentifierPrefix writes it
        XCTAssertNil(PushToken.team(""))
        XCTAssertNil(PushToken.team("$(DEVELOPMENT_TEAM)"))
        XCTAssertNil(PushToken.team("abcde12345"))
    }

    func testWhichTokenAnswers() {
        let base = URL(string: "https://pc.example.ts.net:10005")!
        let pass = AnswerPass(baseURL: base, token: "answer")
        let pairing = Pairing(baseURL: base, token: "full", pairedAt: Date(), pcName: "pc")
        // locked: only the answer pass can be read
        XCTAssertEqual(PushAnswerer.credentials(pass: pass, pairing: nil)?.token, "answer")
        // unlocked: still the narrower one
        XCTAssertEqual(PushAnswerer.credentials(pass: pass, pairing: pairing)?.token, "answer")
        // no pass yet (registered before a233's PC, or lost): the pairing's while it can be read
        XCTAssertEqual(PushAnswerer.credentials(pass: nil, pairing: pairing)?.token, "full")
        // a pass for another PC (paired again elsewhere) is not used
        let other = Pairing(baseURL: URL(string: "https://other.example.ts.net:10005")!, token: "full2", pairedAt: Date(), pcName: "o")
        XCTAssertEqual(PushAnswerer.credentials(pass: pass, pairing: other)?.token, "full2")
        XCTAssertNil(PushAnswerer.credentials(pass: nil, pairing: nil))
    }

    func testRegistrationBody() throws {
        let body = PushRegistration(token: "ab", environment: "production", device: "iPhone", team: nil, answer: true)
        let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
        XCTAssertEqual(back["token"] as? String, "ab")
        XCTAssertEqual(back["answer"] as? Bool, true)
        let reply = try JSONDecoder().decode(PushRegisterReply.self, from: Data(#"{"ok": true, "answerToken": "t", "push": {"on": false, "text": "Push is off: no APNs key.", "phones": 1}}"#.utf8))
        XCTAssertEqual(reply.answerToken, "t")
        XCTAssertEqual(reply.push?.on, false)
    }

    func testAnswerPassStore() throws {
        let pass = AnswerPass(baseURL: URL(string: "https://pc.example.ts.net:10005")!, token: "t")
        AnswerPassStore.clear()
        XCTAssertNil(AnswerPassStore.load())
        // the CI simulator's test host is unsigned, and an unsigned app may get no Keychain
        try XCTSkipUnless(AnswerPassStore.save(pass), "no Keychain for this unsigned test host")
        XCTAssertEqual(AnswerPassStore.load(), pass)
        AnswerPassStore.clear()
        XCTAssertNil(AnswerPassStore.load())
    }
}
