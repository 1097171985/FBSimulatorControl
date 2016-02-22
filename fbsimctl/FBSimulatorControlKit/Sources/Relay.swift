/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

/**
 A Protocol for instances that act as sinks of and sources of lines.
 */
protocol Relay {
  func start()
  func stop()
}

/**
  A Class to report the Relay Lifecycle to.
*/
struct RelayReporter {
  let reporter: EventReporter
  let subject: EventReporterSubject

  func started() {
    self.reporter.reportSimple(EventName.Listen, EventType.Started, self.subject)
  }

  func ended(error: String?) {
    if let error = error {
      self.reporter.reportSimpleBridge(EventName.Failure, EventType.Discrete, error as NSString)
    }
    self.reporter.reportSimple(EventName.Listen, EventType.Ended, self.subject)
  }
}

/**
 A Connection of Reporter-to-Transformer, linebuffering an input
 */
class RelayConnection : LineBufferDelegate {
  let performer: CommandPerformer
  let reporter: EventReporter
  lazy var lineBuffer: LineBuffer = LineBuffer(delegate: self)

  init (performer: CommandPerformer, reporter: EventReporter) {
    self.performer = performer
    self.reporter = reporter
  }

  func buffer(lineAvailable: String) {
    let result = self.performer.perform(lineAvailable, reporter: self.reporter)
    switch result {
    case .Failure(let error):
      self.reporter.reportSimpleBridge(EventName.Failure, EventType.Discrete, error as NSString)
    default:
      break
    }
  }
}
