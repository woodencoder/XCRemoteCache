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

/// Abstract class for consumer's consumer and producer plugins
class ThinningConsumerPlugin {
    private var wasRun: Bool = false

    deinit {
        // initialised but never run plugin suggests that standard target fallbacks to the local development
        // and DerivedData still misses build artifacts.
        guard wasRun else {
            let errorMessage = """
            \(type(of: self)) plugin has never been run, thinning cannot be supported. Verify you \
            have active network connection to the remote cache server or fallback to the non-thinned mode.
            """
            exit(1, errorMessage)
        }
    }

    /// called when plugin is run
    func onRun() {
        wasRun = true
    }
}
