import os
import Testing
@testable import OtterCore

@Test func loggerSubsystemMatchesBundleIdentifier() {
    #expect(Logger.subsystem == "io.github.elizabeth-ling.otter")
}
