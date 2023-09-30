//
//  JobExecutionError.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public enum JobExecutionError: JobError {

  public enum InvariantViolation: Codable {
    case inputResultMissing
    case inputResultInvalid
    case executeInvokedWithFailedInput
  }

  case invariantViolation(InvariantViolation)
  case multipleInputsFailed([Error])
  case unboundInputs(jobType: String, inputTypes: [String])

  public static func unboundInputs(jobType: Any.Type, inputTypes: [Any.Type]) -> Self {
    return .unboundInputs(jobType: String(reflecting: jobType), inputTypes: inputTypes.map { String(reflecting: $0) })
  }

  enum CodingKeys: CodingKey {
    case invariantViolation
    case multipleInputsFailed
    case unboundInputs
  }

  enum UnboundInputsCodingKeys: CodingKey {
    case jobType
    case inputTypes
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.invariantViolation) {
      self = .invariantViolation(try container.decode(InvariantViolation.self, forKey: .invariantViolation))
    }
    else if container.contains(.multipleInputsFailed) {
      self = .multipleInputsFailed(try container.decode([JobErrorBox].self, forKey: .unboundInputs).map(\.error))
    }
    else if container.contains(.unboundInputs) {
      let nestedContainer = try container.nestedContainer(keyedBy: UnboundInputsCodingKeys.self, forKey: .unboundInputs)
      self = .unboundInputs(jobType: try nestedContainer.decode(String.self, forKey: .jobType),
                            inputTypes: try nestedContainer.decode([String].self, forKey: .inputTypes))
    }
    else {
      throw DecodingError.typeMismatch(Self.self, .init(codingPath: container.codingPath,
                                                        debugDescription: "No matching enumeration key found"))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .invariantViolation(let violation):
      try container.encode(violation, forKey: .invariantViolation)

    case .multipleInputsFailed(let errors):
      try container.encode(errors.map { JobErrorBox($0) }, forKey: .multipleInputsFailed)

    case .unboundInputs(jobType: let jobType, inputTypes: let inputTypes):
      var nestedContainer = container.nestedContainer(keyedBy: UnboundInputsCodingKeys.self, forKey: .unboundInputs)
      try nestedContainer.encode(jobType, forKey: .jobType)
      try nestedContainer.encode(inputTypes, forKey: .inputTypes)
    }
  }
}
