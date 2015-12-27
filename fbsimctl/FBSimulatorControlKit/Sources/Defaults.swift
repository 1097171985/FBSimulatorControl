/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

public protocol Default {
  static func defaultValue() -> Self
}

extension Configuration : Default {
  public static func defaultValue() -> Configuration {
    return Configuration(
      simulatorApplication: try! FBSimulatorApplication(error: ()),
      deviceSetPath: nil,
      options: FBSimulatorManagementOptions()
    )
  }
}

extension Format : Default {
  public static func defaultValue() -> Format {
    return .Compound([ .UDID, .Name])
  }
}

extension Query : Default {
  public static func defaultValue() -> Query {
    return .And([])
  }
}