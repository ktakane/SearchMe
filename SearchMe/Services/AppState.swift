import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var myMemberId: String = UserDefaults.standard.string(forKey: "myMemberId") ?? ""
    @Published var myName: String     = UserDefaults.standard.string(forKey: "myName") ?? ""
    @Published var groupId: String    = UserDefaults.standard.string(forKey: "groupId") ?? ""
    @Published var groupName: String  = UserDefaults.standard.string(forKey: "groupName") ?? ""
    @Published var inviteCode: String = UserDefaults.standard.string(forKey: "inviteCode") ?? ""
    @Published var isOwner: Bool = UserDefaults.standard.bool(forKey: "isOwner") {
        didSet { UserDefaults.standard.set(isOwner, forKey: "isOwner") }
    }
    @Published var isDisasterMode: Bool = UserDefaults.standard.bool(forKey: "isDisasterMode") {
        didSet { UserDefaults.standard.set(isDisasterMode, forKey: "isDisasterMode") }
    }
    @Published var showSafetyReminder: Bool = false

    var isSetupComplete: Bool { !myMemberId.isEmpty && !groupId.isEmpty }

    func save() {
        UserDefaults.standard.set(myMemberId, forKey: "myMemberId")
        UserDefaults.standard.set(myName,     forKey: "myName")
        UserDefaults.standard.set(groupId,    forKey: "groupId")
        UserDefaults.standard.set(groupName,  forKey: "groupName")
        UserDefaults.standard.set(inviteCode, forKey: "inviteCode")
        UserDefaults.standard.set(isOwner,    forKey: "isOwner")
    }

    func register(memberId: String, name: String, groupId: String, groupName: String, inviteCode: String, isOwner: Bool) {
        self.myMemberId = memberId
        self.myName     = name
        self.groupId    = groupId
        self.groupName  = groupName
        self.inviteCode = inviteCode
        self.isOwner    = isOwner
        save()
    }

    func clearGroup() {
        myMemberId = ""; myName = ""; groupId = ""; groupName = ""; inviteCode = ""; isOwner = false
        ["myMemberId","myName","groupId","groupName","inviteCode","isOwner"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }
}
