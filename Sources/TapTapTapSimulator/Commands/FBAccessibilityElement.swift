/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


import TapTapTapCore
import Foundation

/// An open accessibility element. Holds the translation request's token until closed.
public final class FBAccessibilityElement {

  private let element: FBAXPlatformElement
  private let request: FBAXTranslationRequest
  private let dispatcher: FBAXTranslationDispatcher
  private var closed: Bool = false

  init(element: FBAXPlatformElement, request: FBAXTranslationRequest, dispatcher: FBAXTranslationDispatcher) {
    self.element = element
    self.request = request
    self.dispatcher = dispatcher
  }

  deinit {
    close()
  }

  // MARK: - Lifecycle

  public func close() {
    if !closed {
      closed = true
      dispatcher.popRequest(request)
    }
  }

  // MARK: - Serialization

  public func serialize(with options: FBAccessibilityRequestOptions) throws -> FBAccessibilityElementsResponse {
    if closed {
      throw FBAccessibilityError.closedElement(operation: "serialize")
    }
    return request.run(element, options: options)
  }
}
