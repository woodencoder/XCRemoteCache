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

enum PrebuildContextError: Error {
    case missingEnv(String)
    case invalidAddress(String)
}

public struct PrebuildContext {
    let targetTempDir: URL
    let productsDir: URL
    let moduleName: String?
    /// Commit sha of the commit to use remote cache
    let remoteCommit: RemoteCommitInfo
    /// Location of the file that specifies remote commit sha
    let remoteCommitLocation: URL
    let recommendedCacheAddress: URL
    /// Force using the cached artifact and never fallback to the local compilation
    let forceCached: Bool
    /// A file that stores a list of all target compilation invocations so far
    let compilationHistoryFile: URL
    /// If true, any request timeout disables remote cache for all targets
    let turnOffRemoteCacheOnFirstTimeout: Bool
    /// Name of a target
    let targetName: String
    /// List of all targets to downloaded from the thinning aggregation target
    var thinnedTargets: [String]?
}

extension PrebuildContext {
    init(_ config: XCRemoteCacheConfig, env: [String: String]) throws {
        targetTempDir = try env.readEnv(key: "TARGET_TEMP_DIR")
        productsDir = try env.readEnv(key: "BUILT_PRODUCTS_DIR")
        moduleName = env.readEnv(key: "PRODUCT_MODULE_NAME")
        let srcRoot: URL = try env.readEnv(key: "SRCROOT")
        remoteCommitLocation = URL(fileURLWithPath: config.remoteCommitFile, relativeTo: srcRoot)
        remoteCommit = RemoteCommitInfo(try? String(contentsOf: remoteCommitLocation).trim())
        guard let address = URL(string: config.recommendedCacheAddress) else {
            throw PrebuildContextError.invalidAddress(config.recommendedCacheAddress)
        }
        recommendedCacheAddress = address
        let targetName: String = try env.readEnv(key: "TARGET_NAME")
        forceCached = !config.focusedTargets.isEmpty && !config.focusedTargets.contains(targetName)
        compilationHistoryFile = targetTempDir.appendingPathComponent(config.compilationHistoryFile)
        turnOffRemoteCacheOnFirstTimeout = config.turnOffRemoteCacheOnFirstTimeout
        self.targetName = targetName
        let thinFocusedTargetsString: String? = env.readEnv(key: "SPT_XCREMOTE_CACHE_THINNED_TARGETS")
        thinnedTargets = thinFocusedTargetsString?.split(separator: ",").map(String.init)
    }
}
