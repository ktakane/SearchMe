import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var myMemberId: String = UserDefaults.standard.string(forKey: "myMemberId") ?? ""
    @Published var myName: String     = UserDefaults.standard.string(forKey: "myName") ?? ""
    @Published var groupId: String    = UserDefaults.standard.string(forKey: "groupId") ?? ""
    @Published var groupName: String  = UserDefaults.standard.string(forKey: "groupName") ?? ""
    @Published var inviteCode: String = UserDefaults.standard.string(forKey: "inviteCode") ?? ""
    @Published var isDisasterMode: Bool = false

    var isSetupComplete: Bool { !myMemberId.isEmpty && !groupId.isEmpty }

    func save() {
        UserDefaults.standard.set(myMemberId, forKey: "myMemberId")
        UserDefaults.standard.set(myName,     forKey: "myName")
        UserDefaults.standard.set(groupId,    forKey: "groupId")
        UserDefaults.standard.set(groupName,  forKey: "groupName")
        UserDefaults.standard.set(inviteCode, forKey: "inviteCode")
    }

    func register(memberId: String, name: String, groupId: String, groupName: String, inviteCode: String) {
        self.myMemberId = memberId
        self.myName     = name
        self.groupId    = groupId
        self.groupName  = groupName
        self.inviteCode = inviteCode
        save()
    }
}
