//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basic

public protocol Message: Codable, CustomStringConvertible {}

public extension Message {
  func write(to stream: FileOutputByteStream) throws {
    let data: Data = try JSONEncoder().encode(self)
    // messages are separated by newlines
    stream <<< data <<< "\n"
    stream.flush()
  }

  init?(from data: Data) {
    guard let message = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
    self = message
  }
}

public enum StressTesterMessage: Message {
  case detected(SourceKitError)
}

public enum SourceKitError: Error {
  case crashed(request: RequestInfo)
  case timedOut(request: RequestInfo)
  case failed(_ reason: SourceKitErrorReason, request: RequestInfo, response: String)

  public var request: RequestInfo {
    switch self {
    case .crashed(let request):
      return request
    case .timedOut(let request):
      return request
    case .failed(_, let request, _):
      return request
    }
  }
}

public enum SourceKitErrorReason: String, Codable {
  case errorResponse, errorTypeInResponse, errorDeserializingSyntaxTree, sourceAndSyntaxTreeMismatch
}

public enum RequestInfo {
  case editorOpen(document: DocumentInfo)
  case editorClose(document: DocumentInfo)
  case editorReplaceText(document: DocumentInfo, offset: Int, length: Int, text: String)
  case cursorInfo(document: DocumentInfo, offset: Int, args: [String])
  case codeComplete(document: DocumentInfo, offset: Int, args: [String])
  case rangeInfo(document: DocumentInfo, offset: Int, length: Int, args: [String])
  case semanticRefactoring(document: DocumentInfo, offset: Int, kind: String, args: [String])
}

public struct DocumentInfo: Codable {
  public let path: String
  public let modification: DocumentModification?

  public init(path: String, modification: DocumentModification? = nil) {
    self.path = path
    self.modification = modification
  }
}

public struct DocumentModification: Codable {
  public let mode: RewriteMode
  public let content: String

  public init(mode: RewriteMode, content: String) {
    self.mode = mode
    self.content = content
  }
}

public enum RewriteMode: String, Codable {
  /// Do not rewrite the file (only make non-modifying SourceKit requests)
  case none
  /// Rewrite the file token by token, top to bottom
  case basic
  /// Rewrite all top level declarations top to bottom, concurrently
  case concurrent
  /// Rewrite the file from the most deeply nested tokens to the least
  case insideOut
}

public struct Page: Codable {
  public let number: Int
  public let count: Int
  public var isFirst: Bool {
    return number == 1
  }
  public var index: Int {
    return number - 1
  }

  public init(_ number: Int, of count: Int) {
    assert(number >= 1 && number <= count)
    self.number = number
    self.count = count
  }
}

extension StressTesterMessage: Codable {
  enum CodingKeys: String, CodingKey {
    case message, error
  }
  enum BaseMessage: String, Codable {
    case detected
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseMessage.self, forKey: .message) {
    case .detected:
      let error = try container.decode(SourceKitError.self, forKey: .error)
      self = .detected(error)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .detected(let error):
      try container.encode(BaseMessage.detected, forKey: .message)
      try container.encode(error, forKey: .error)
    }
  }
}

extension SourceKitError: Codable {
  enum CodingKeys: String, CodingKey {
    case error, kind, request, response
  }
  enum BaseError: String, Codable {
    case crashed, failed, timedOut
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseError.self, forKey: .error) {
    case .crashed:
      let request = try container.decode(RequestInfo.self, forKey: .request)
      self = .crashed(request: request)
    case .timedOut:
      let request = try container.decode(RequestInfo.self, forKey: .request)
      self = .timedOut(request: request)
    case .failed:
      let reason = try container.decode(SourceKitErrorReason.self, forKey: .kind)
      let request = try container.decode(RequestInfo.self, forKey: .request)
      let response = try container.decode(String.self, forKey: .response)
      self = .failed(reason, request: request, response: response)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .crashed(let request):
      try container.encode(BaseError.crashed, forKey: .error)
      try container.encode(request, forKey: .request)
    case .timedOut(let request):
      try container.encode(BaseError.timedOut, forKey: .error)
      try container.encode(request, forKey: .request)
    case .failed(let kind, let request, let response):
      try container.encode(BaseError.failed, forKey: .error)
      try container.encode(kind, forKey: .kind)
      try container.encode(request, forKey: .request)
      try container.encode(response, forKey: .response)
    }
  }
}

extension RequestInfo: Codable {
  enum CodingKeys: String, CodingKey {
    case request, kind, document, offset, length, text, args
  }
  enum BaseRequest: String, Codable {
    case editorOpen, editorClose, replaceText, cursorInfo, codeComplete, rangeInfo, semanticRefactoring
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseRequest.self, forKey: .request) {
    case .editorOpen:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      self = .editorOpen(document: document)
    case .editorClose:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      self = .editorClose(document: document)
    case .cursorInfo:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let args = try container.decode([String].self, forKey: .args)
      self = .cursorInfo(document: document, offset: offset, args: args)
    case .codeComplete:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let args = try container.decode([String].self, forKey: .args)
      self = .codeComplete(document: document, offset: offset, args: args)
    case .rangeInfo:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      let args = try container.decode([String].self, forKey: .args)
      self = .rangeInfo(document: document, offset: offset, length: length, args: args)
    case .semanticRefactoring:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let kind = try container.decode(String.self, forKey: .kind)
      let args = try container.decode([String].self, forKey: .args)
      self = .semanticRefactoring(document: document, offset: offset, kind: kind, args: args)
    case .replaceText:
      let document = try container.decode(DocumentInfo.self, forKey: .document)
      let offset = try container.decode(Int.self, forKey: .offset)
      let length = try container.decode(Int.self, forKey: .length)
      let text = try container.decode(String.self, forKey: .text)
      self = .editorReplaceText(document: document, offset: offset, length: length, text: text)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .editorOpen(let document):
      try container.encode(BaseRequest.editorOpen, forKey: .request)
      try container.encode(document, forKey: .document)
    case .editorClose(let document):
      try container.encode(BaseRequest.editorClose, forKey: .request)
      try container.encode(document, forKey: .document)
    case .cursorInfo(let document, let offset, let args):
      try container.encode(BaseRequest.cursorInfo, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(args, forKey: .args)
    case .codeComplete(let document, let offset, let args):
      try container.encode(BaseRequest.codeComplete, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(args, forKey: .args)
    case .rangeInfo(let document, let offset, let length, let args):
      try container.encode(BaseRequest.rangeInfo, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(length, forKey: .length)
      try container.encode(args, forKey: .args)
    case .semanticRefactoring(let document, let offset, let kind, let args):
      try container.encode(BaseRequest.semanticRefactoring, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(kind, forKey: .kind)
      try container.encode(args, forKey: .args)
    case .editorReplaceText(let document, let offset, let length, let text):
      try container.encode(BaseRequest.replaceText, forKey: .request)
      try container.encode(document, forKey: .document)
      try container.encode(offset, forKey: .offset)
      try container.encode(length, forKey: .length)
      try container.encode(text, forKey: .text)
    }
  }
}

extension RequestInfo: CustomStringConvertible {
  public var description: String {
    switch self {
    case .editorOpen(let document):
      return "EditorOpen on \(document)"
    case .editorClose(let document):
      return "EditorClose on \(document)"
    case .cursorInfo(let document, let offset, let args):
      return "CursorInfo in \(document) at offset \(offset) with args: \(args.joined(separator: " "))"
    case .rangeInfo(let document, let offset, let length, let args):
      return "RangeInfo in \(document) at offset \(offset) for length \(length) with args: \(args.joined(separator: " "))"
    case .codeComplete(let document, let offset, let args):
      return "CodeComplete in \(document) at offset \(offset) with args: \(args.joined(separator: " "))"
    case .semanticRefactoring(let document, let offset, let kind, let args):
      return "SemanticRefactoring (\(kind)) in \(document) at offset \(offset) with args: \(args.joined(separator: " "))"
    case .editorReplaceText(let document, let offset, let length, let text):
      return "ReplaceText in \(document) at offset \(offset) for length \(length) with text: \(text)"
    }
  }
}

extension DocumentInfo: CustomStringConvertible {
  public var description: String {
    guard let modification = modification else {
      return path
    }
    return "\(path) (modified: \(modification.mode.rawValue))"
  }
}

extension SourceKitErrorReason: CustomStringConvertible {
  public var description: String {
    switch self {
    case .errorResponse:
      return "SourceKit returned an error response"
    case .errorTypeInResponse:
      return "SourceKit returned a response containing <<error type>>"
    case .errorDeserializingSyntaxTree:
      return "SourceKit returned a response with invalid SyntaxTree data"
    case .sourceAndSyntaxTreeMismatch:
      return "SourceKit returned a syntax tree that doesn't match the expected source"
    }
  }
}

extension SourceKitError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .crashed(let request):
      return """
        SourceKit crashed
          request: \(request)
        -- begin file content --------
        \(markSourceLocation(of: request) ?? "<unmodified>")
        -- end file content ----------
        """
    case .timedOut(let request):
      return """
        Timed out waiting for SourceKit response
          request: \(request)
        -- begin file content --------
        \(markSourceLocation(of: request) ?? "<unmodified>")
        -- end file content ----------
        """
    case .failed(let reason, let request, let response):
      return """
        \(reason)
          request: \(request)
          response: \(response)
        -- begin file content --------
        \(markSourceLocation(of: request) ?? "<unmodified>")
        -- end file content ----------
        """
    }
  }

  private func markSourceLocation(of request: RequestInfo) -> String? {
    switch request {
    case .editorOpen(let document):
      return document.modification?.content
    case .editorClose(let document):
      return document.modification?.content
    case .editorReplaceText(let document, let offset, let length, _):
      guard let source = document.modification?.content else { return nil }
      let startIndex = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let endIndex = source.utf8.index(source.utf8.startIndex, offsetBy: offset + length)
      let prefix = source.prefix(upTo: startIndex)
      let replace = source.dropFirst(offset).prefix(length)
      let suffix = source.suffix(from: endIndex)
      return String(prefix) + "<replace-start>" + String(replace) + "<replace-end>" + String(suffix)
    case .cursorInfo(let document, let offset, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = source.prefix(upTo: index)
      let suffix = source.suffix(from: index)
      return String(prefix) + "<cursor-offset>" + String(suffix)
    case .codeComplete(let document, let offset, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = source.prefix(upTo: index)
      let suffix = source.suffix(from: index)
      return String(prefix) + "<complete-offset>" + String(suffix)
    case .rangeInfo(let document, let offset, let length, _):
      guard let source = document.modification?.content else { return nil }
      let startIndex = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let endIndex = source.utf8.index(source.utf8.startIndex, offsetBy: offset + length)
      let prefix = source.prefix(upTo: startIndex)
      let replace = source.dropFirst(offset).prefix(length)
      let suffix = source.suffix(from: endIndex)
      return String(prefix) + "<range-start>" + String(replace) + "<range-end>" + String(suffix)
    case .semanticRefactoring(let document, let offset, _, _):
      guard let source = document.modification?.content else { return nil }
      let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
      let prefix = source.prefix(upTo: index)
      let suffix = source.suffix(from: index)
      return String(prefix) + "<refactor-offset>" + String(suffix)
    }
  }
}

extension StressTesterMessage: CustomStringConvertible {
  public var description: String {
    switch self {
    case .detected(let error):
      return "Failure detected: \(error)"
    }
  }
}
