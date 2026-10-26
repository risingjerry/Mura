import Foundation
import MuraCore

let env = ProcessInfo.processInfo.environment
let output = Mura(home: Home.resolve(env: env), desktop: MacDesktop(), env: env).run(Array(CommandLine.arguments.dropFirst()))
print(output.json)
exit(output.exitCode)
