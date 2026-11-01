import Foundation
let cmd = CommandLine.arguments.dropFirst().joined(separator: " ")
DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.wquguru.cicada.debug"), object: cmd, userInfo: nil, deliverImmediately: true)
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
