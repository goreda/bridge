import Foundation
let client=IPCClient(path:CommandLine.arguments[1])
for i in 0..<500 {
 client.sendLatestPose("{\"command\":[\"pose\",\(i)]}")
 if i==100 {client.send("{\"command\":[\"key\",\"pause\"]}")}
}
Thread.sleep(forTimeInterval:1)
client.closeLatestPose()
client.send("{\"command\":[\"quit\"]}")
for i in 500..<1000 {client.sendLatestPose("{\"command\":[\"pose\",\(i)]}")}
Thread.sleep(forTimeInterval:0.5)
