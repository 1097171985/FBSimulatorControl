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

public protocol EventReporter {
  func report(subject: EventReporterSubject)
}

extension EventReporter {
  func reportSimpleBridge(eventName: EventName, _ eventType: EventType, _ subject: SimulatorControlSubject) {
    self.reportSimple(eventName, eventType, SimulatorControlSubjectBridge(subject))
  }

  func reportSimple(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.report(SimpleEvent(eventName, eventType, subject))
  }
}

public class EventSinkTranslator : NSObject, FBSimulatorEventSink {
  unowned let simulator: FBSimulator
  let reporter: EventReporter
  let format: Format

  init(simulator: FBSimulator, format: Format, reporter: EventReporter) {
    self.simulator = simulator
    self.reporter = reporter
    self.format = format
    super.init()
    self.simulator.userEventSink = self
  }

  public func containerApplicationDidLaunch(applicationProcess: FBProcessInfo!) {
    self.reportSimulator(EventName.Launch, applicationProcess)
  }

  public func containerApplicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, applicationProcess)
  }

  public func bridgeDidConnect(bridge: FBSimulatorBridge!) {
    self.reportSimulator(EventName.Launch, bridge)
  }

  public func bridgeDidDisconnect(bridge: FBSimulatorBridge!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, bridge)
  }

  public func simulatorDidLaunch(launchdSimProcess: FBProcessInfo!) {
    self.reportSimulator(EventName.Launch, launchdSimProcess)
  }

  public func simulatorDidTerminate(launchdSimProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, launchdSimProcess)
  }

  public func agentDidLaunch(launchConfig: FBAgentLaunchConfiguration!, didStart agentProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.reportSimulator(EventName.Launch, agentProcess)
  }

  public func agentDidTerminate(agentProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, agentProcess)
  }

  public func applicationDidLaunch(launchConfig: FBApplicationLaunchConfiguration!, didStart applicationProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.reportSimulator(EventName.Launch, applicationProcess)
  }

  public func applicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, applicationProcess)
  }

  public func diagnosticAvailable(log: FBDiagnostic!) {
    self.reportSimulator(EventName.Diagnostic, log)
  }

  public func didChangeState(state: FBSimulatorState) {
    self.reportSimulator(EventName.StateChange, state.description as NSString)
  }

  public func terminationHandleAvailable(terminationHandle: FBTerminationHandleProtocol!) {

  }
}

extension EventSinkTranslator {
  public func reportSimulator(eventName: EventName, _ eventType: EventType, _ subject: SimulatorControlSubject) {
    self.reporter.report(SimulatorEvent(
      simulator: self.simulator,
      format: self.format,
      eventName: eventName,
      eventType: eventType,
      subject: subject
    ))
  }

  public func reportSimulator(eventName: EventName, _ subject: SimulatorControlSubject) {
    self.reportSimulator(eventName, EventType.Discrete, subject)
  }
}

public class HumanReadableEventReporter : EventReporter {
  let writer: Writer

  init(writer: Writer) {
    self.writer = writer
  }

  public func report(subject: EventReporterSubject) {
    self.writer.write(subject.description)
  }
}

@objc public class JSONEventReporter : NSObject, EventReporter {
  let writer: Writer
  let pretty: Bool

  init(writer: Writer, pretty: Bool) {
    self.writer = writer
    self.pretty = pretty
  }

  public func report(subject: EventReporterSubject) {
    self.writer.write(try! subject.jsonDescription.serializeToString(pretty) as String)
  }

  public func reportLogBridge(subject: LogEvent) {
    self.report(subject)
  }
}

public extension OutputOptions {
  public func createReporter(writer: Writer) -> EventReporter {
    if self.contains(OutputOptions.JSON) {
      let pretty = self.contains(OutputOptions.Pretty)
      return JSONEventReporter(writer: writer, pretty: pretty)
    }
    return HumanReadableEventReporter(writer: writer)
  }
}

public extension Command {
  public func createReporter(writer: Writer) -> EventReporter {
    switch self {
    case .Help(let outputOptions, _, _):
      return outputOptions.createReporter(writer)
    case .Perform(let configuration, _, _, _):
      return configuration.output.createReporter(writer)
    }
  }
}
