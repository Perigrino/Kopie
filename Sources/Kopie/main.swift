import Foundation

@main
enum Main {
    static func main() {
        if SelfTest.run(Array(CommandLine.arguments.dropFirst())) { return }
        KopieApp.main()
    }
}
