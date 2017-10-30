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

extension FileOutput {
  func makeWriter() throws -> FBFileWriter {
    switch self {
    case .path(let path):
      return try FBFileWriter.syncWriter(forFilePath: path)
    case .standardOut:
      return FBFileWriter.syncWriter(with: FileHandle.standardOutput)
    }
  }
}

struct SimulatorCreationRunner : Runner {
  let context: iOSRunnerContext<CreationSpecification>

  func run() -> CommandResult {
    do {
      for configuration in self.configurations {
        self.context.reporter.reportSimpleBridge(.create, .started, configuration)
        let simulator = try self.context.simulatorControl.set.createSimulator(with: configuration)
        self.context.defaults.updateLastQuery(FBiOSTargetQuery.udids([simulator.udid]))
        self.context.reporter.reportSimpleBridge(.create, .ended, simulator)
      }
      return .success(nil)
    } catch let error as NSError {
      return .failure("Failed to Create Simulator \(error.description)")
    }
  }

  fileprivate var configurations: [FBSimulatorConfiguration] { get {
    switch self.context.value {
    case .allMissingDefaults:
      return  self.context.simulatorControl.set.configurationsForAbsentDefaultSimulators()
    case .individual(let configuration):
      return [configuration.simulatorConfiguration]
    }
  }}
}

struct SimulatorActionRunner : Runner {
  let context: iOSRunnerContext<(Action, FBSimulator)>

  func run() -> CommandResult {
    let (action, simulator) = self.context.value
    let reporter = SimulatorReporter(simulator: simulator, format: self.context.format, reporter: self.context.reporter)
    defer {
      simulator.userEventSink = nil
    }
    let context = self.context.replace((action, simulator, reporter))
    return SimulatorActionRunner.makeRunner(context).run()
  }

  static func makeRunner(_ context: iOSRunnerContext<(Action, FBSimulator, SimulatorReporter)>) -> Runner {
    let (action, simulator, reporter) = context.value
    let covariantTuple: (Action, FBiOSTarget, iOSReporter) = (action, simulator, reporter)
    if let runner = iOSActionProvider(context: context.replace(covariantTuple)).makeRunner() {
      return runner
    }

    switch action {
    case .clearKeychain(let maybeBundleID):
      return iOSTargetRunner.simple(reporter, .clearKeychain, simulator.subject) {
        if let bundleID = maybeBundleID {
          try simulator.killApplication(withBundleID: bundleID).await()
        }
        try simulator.clearKeychain()
      }
    case .delete:
      return iOSTargetRunner.simple(reporter, .delete, simulator.subject) {
        try simulator.set!.delete(simulator)
      }
    case .erase:
      return iOSTargetRunner.simple(reporter, .erase, simulator.subject) {
        try simulator.erase()
      }
    case .focus:
      return iOSTargetRunner.simple(reporter, .focus, simulator.subject) {
        try simulator.focus()
      }
    case .keyboardOverride:
      return iOSTargetRunner.future(
        reporter,
        .keyboardOverride,
        simulator.subject,
        simulator.setupKeyboard()
      )
    case .open(let url):
      return iOSTargetRunner.simple(reporter, .open, FBEventReporterSubject(string: url.bridgedAbsoluteString)) {
        try simulator.open(url)
      }
    case .relaunch(let appLaunch):
      return FutureRunner(reporter, .relaunch, appLaunch.subject, simulator.launchOrRelaunchApplication(appLaunch))
    case .shutdown:
      return iOSTargetRunner.simple(reporter, .shutdown, simulator.subject) {
        try simulator.set!.kill(simulator)
      }
    case .setLocation(let latitude, let longitude):
      return iOSTargetRunner.simple(reporter, .setLocation, simulator.subject) {
        try simulator.setLocation(latitude, longitude: longitude)
      }
    case .upload(let diagnostics):
      return UploadRunner(reporter, diagnostics)
    case .watchdogOverride(let bundleIDs, let timeout):
      return FutureRunner(
        reporter,
        .watchdogOverride,
        FBEventReporterSubject(strings: bundleIDs),
        simulator.overrideWatchDogTimer(forApplications: bundleIDs, withTimeout: timeout)
      )
    default:
      return CommandResultRunner.unimplementedActionRunner(action, target: simulator, format: context.format)
    }
  }
}

private struct UploadRunner : Runner {
  let reporter: SimulatorReporter
  let diagnostics: [FBDiagnostic]

  init(_ reporter: SimulatorReporter, _ diagnostics: [FBDiagnostic]) {
    self.reporter = reporter
    self.diagnostics = diagnostics
  }

  func run() -> CommandResult {
    var diagnosticLocations: [(FBDiagnostic, String)] = []
    for diagnostic in diagnostics {
      guard let localPath = diagnostic.asPath else {
        return .failure("Could not get a local path for diagnostic \(diagnostic)")
      }
      diagnosticLocations.append((diagnostic, localPath))
    }

    let mediaPredicate = NSPredicate.forMediaPaths()
    let media = diagnosticLocations.filter { (_, location) in
      mediaPredicate.evaluate(with: location)
    }

    if media.count > 0 {
      let paths = media.map { $0.1 }
      let runner = iOSTargetRunner.simple(reporter, .upload, FBEventReporterSubject(strings: paths)) {
        try FBUploadMediaStrategy(simulator: self.reporter.simulator).uploadMedia(paths)
      }
      let result = runner.run()
      switch result.outcome {
      case .failure: return result
      default: break
      }
    }

    let basePath = self.reporter.simulator.auxillaryDirectory
    let arbitraryPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: mediaPredicate)
    let arbitrary = diagnosticLocations.filter{ arbitraryPredicate.evaluate(with: $0.1) }
    for (sourceDiagnostic, sourcePath) in arbitrary {
      guard let destinationPath = try? sourceDiagnostic.writeOut(toDirectory: basePath as String) else {
        return CommandResult.failure("Could not write out diagnostic \(sourcePath) to path")
      }
      let destinationDiagnostic = FBDiagnosticBuilder().updatePath(destinationPath).build()
      self.reporter.report(.upload, .discrete, destinationDiagnostic.subject)
    }

    return .success(nil)
  }
}
