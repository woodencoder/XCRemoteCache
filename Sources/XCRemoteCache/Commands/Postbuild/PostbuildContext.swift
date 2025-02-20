// Copyright (c) 2021 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation


enum MachOType: String, Codable {
    case staticLib
    case dynamicLib = "mh_dylib"
    case executable = "mh_execute"
    case bundle = "mh_bundle"
    case relocatable = "mh_object"
    case unknown
}

enum PostbuildContextError: Error {
    /// URL address is not a valid URL
    case invalidAddress(String)
}

public struct PostbuildContext {
    var mode: Mode
    var targetName: String
    var targetTempDir: URL
    /// Location where all compilation outputs (.o) are placed
    var compilationTempDir: URL
    var configuration: String
    var platform: String
    var productsDir: URL
    var moduleName: String?
    /// Path to the *.swiftmodule directory (irrelevant when `module` is nil). Rrelative to `productsDir`
    var modulesFolderPath: String
    var executablePath: String
    var srcRoot: URL
    var xcodeDir: URL
    var xcodeBuildNumber: String
    /// Location of the file that specifies remote commit sha
    var remoteCommitLocation: URL
    /// Commit sha of the commit to use remote cache
    var remoteCommit: RemoteCommitInfo
    var recommendedCacheAddress: URL
    /// All cache adresses to upload cache artifacts (for a producer)
    var cacheAddresses: [URL]
    /// Root directory where all statistics are stored
    var statsLocation: URL
    /// Force using the cached artifact and never fallback to the local compilation
    var forceCached: Bool
    var machOType: MachOType
    var wasDsymGenerated: Bool
    var dSYMPath: URL
    let arch: String
    let builtProductsDir: URL
    /// Location to the product bundle. Can be nil for libraries
    let bundleDir: URL?
    let derivedSourcesDir: URL
    /// List of all targets to downloaded from the thinning aggregation target
    var thinnedTargets: [String]
    /// Action type: build, indexbuild etc.
    var action: BuildActionType
}

extension PostbuildContext {
    init(_ config: XCRemoteCacheConfig, env: [String: String]) throws {
        mode = config.mode
        let targetNameValue: String = try env.readEnv(key: "TARGET_NAME")
        targetName = targetNameValue
        targetTempDir = try env.readEnv(key: "TARGET_TEMP_DIR")
        arch = try env.readEnv(key: "PLATFORM_PREFERRED_ARCH")
        compilationTempDir = try env.readEnv(key: "OBJECT_FILE_DIR_normal").appendingPathComponent(arch)
        configuration = try env.readEnv(key: "CONFIGURATION")
        platform = try env.readEnv(key: "PLATFORM_NAME")
        xcodeBuildNumber = try env.readEnv(key: "XCODE_PRODUCT_BUILD_VERSION")
        productsDir = try env.readEnv(key: "TARGET_BUILD_DIR")
        moduleName = env.readEnv(key: "PRODUCT_MODULE_NAME")
        modulesFolderPath = env.readEnv(key: "MODULES_FOLDER_PATH") ?? ""
        executablePath = try env.readEnv(key: "EXECUTABLE_PATH")
        srcRoot = try env.readEnv(key: "SRCROOT")
        xcodeDir = try env.readEnv(key: "DEVELOPER_DIR")
        remoteCommitLocation = URL(fileURLWithPath: config.remoteCommitFile, relativeTo: srcRoot)
        remoteCommit = RemoteCommitInfo(try? String(contentsOf: remoteCommitLocation).trim())
        guard let address = URL(string: config.recommendedCacheAddress) else {
            throw PostbuildContextError.invalidAddress(config.recommendedCacheAddress)
        }
        recommendedCacheAddress = address
        statsLocation = URL(fileURLWithPath: config.statsDir.expandingTildeInPath, relativeTo: srcRoot)
        cacheAddresses = try config.cacheAddresses.map(URL.build)
        forceCached = !config.focusedTargets.isEmpty && !config.focusedTargets.contains(targetNameValue)
        machOType = try MachOType(rawValue: env.readEnv(key: "MACH_O_TYPE")) ?? .unknown
        wasDsymGenerated = try env.readEnv(key: "DWARF_DSYM_FILE_SHOULD_ACCOMPANY_PRODUCT")
        dSYMPath = try env.readEnv(key: "DWARF_DSYM_FOLDER_PATH")
            .appendingPathComponent(env.readEnv(key: "DWARF_DSYM_FILE_NAME"))
        builtProductsDir = try env.readEnv(key: "BUILT_PRODUCTS_DIR")
        if let contentsFolderPath = env.readEnv(key: "CONTENTS_FOLDER_PATH") {
            bundleDir = productsDir.appendingPathComponent(contentsFolderPath)
        } else {
            bundleDir = nil
        }
        derivedSourcesDir = try env.readEnv(key: "DERIVED_SOURCES_DIR")
        let thinFocusedTargetsString: String = env.readEnv(key: "SPT_XCREMOTE_CACHE_THINNED_TARGETS") ?? ""
        thinnedTargets = thinFocusedTargetsString.split(separator: ",").map(String.init)
        action = (try? BuildActionType(rawValue: env.readEnv(key: "ACTION"))) ?? .unknown
    }
}
