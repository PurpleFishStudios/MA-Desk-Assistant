//
//  LocalAIService.swift
//  MADeskAssistant
//
//  The local model packages were removed so this project can build on
//  Xcode 27.2. Their macro libraries were compiled with Swift 6.4.0 and
//  this Xcode uses Swift 6.4.2.
//

import Foundation
import Observation

@MainActor
@Observable
final class LocalAIService {
    var isLoading = false
    var loadingError: String?

    let unavailableMessage = """
    Local AI is turned off in this build. The model packages were removed because their macro libraries do not match Xcode 27.2.
    """

    func prepareIfNeeded() async {}
}
