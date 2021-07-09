@testable import XCRemoteCache
import XCTest

class PostbuildContextTests: FileXCTestCase {
    private var config: XCRemoteCacheConfig!
    private var remoteCommitFile: URL!
    private static let SampleEnvs = [
        "TARGET_NAME": "TARGET_NAME",
        "TARGET_TEMP_DIR": "TARGET_TEMP_DIR",
        "PLATFORM_PREFERRED_ARCH": "PLATFORM_PREFERRED_ARCH",
        "OBJECT_FILE_DIR_normal": "OBJECT_FILE_DIR_normal" ,
        "CONFIGURATION": "CONFIGURATION",
        "PLATFORM_NAME": "PLATFORM_NAME",
        "XCODE_PRODUCT_BUILD_VERSION": "XCODE_PRODUCT_BUILD_VERSION",
        "TARGET_BUILD_DIR": "TARGET_BUILD_DIR",
        "PRODUCT_MODULE_NAME": "PRODUCT_MODULE_NAME",
        "EXECUTABLE_PATH": "EXECUTABLE_PATH",
        "SRCROOT": "SRCROOT",
        "DEVELOPER_DIR": "DEVELOPER_DIR",
        "MACH_O_TYPE": "MACH_O_TYPE",
        "DWARF_DSYM_FILE_SHOULD_ACCOMPANY_PRODUCT": "DWARF_DSYM_FILE_SHOULD_ACCOMPANY_PRODUCT",
        "DWARF_DSYM_FOLDER_PATH": "DWARF_DSYM_FOLDER_PATH",
        "DWARF_DSYM_FILE_NAME": "DWARF_DSYM_FILE_NAME",
        "BUILT_PRODUCTS_DIR": "BUILT_PRODUCTS_DIR",
        "DERIVED_SOURCES_DIR": "DERIVED_SOURCES_DIR",
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        let workingDir = try prepareTempDir()
        remoteCommitFile = workingDir.appendingPathComponent("arc.rc")
        _ = workingDir.appendingPathComponent("mpo")
        config = XCRemoteCacheConfig(remoteCommitFile: remoteCommitFile.path, sourceRoot: workingDir.path)
        config.recommendedCacheAddress = "http://test.com"
    }

    func testValidCommitFileSetsValidConsumer() throws {
        try fileManager.write(toPath: remoteCommitFile.path, contents: "123".data(using: .utf8))
        let context = try PostbuildContext(config, env: Self.SampleEnvs)

        XCTAssertEqual(context.remoteCommit, .available(commit: "123"))
    }

    func testEmptyCommitFileSetsUnavailableConsumer() throws {
        try fileManager.write(toPath: remoteCommitFile.path, contents: nil)
        let context = try PostbuildContext(config, env: Self.SampleEnvs)

        XCTAssertEqual(context.remoteCommit, .unavailable)
    }

    func testMissingCommitFileSetsUnavailableConsumer() throws {
        try fileManager.spt_deleteItem(at: remoteCommitFile)
        let context = try PostbuildContext(config, env: Self.SampleEnvs)

        XCTAssertEqual(context.remoteCommit, .unavailable)
    }
}
