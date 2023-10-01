//
//  KubrickTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import CryptoKit
import Foundation
import PotentCBOR
import RegexBuilder
import XCTest
@testable import Kubrick


final class KubrickTests: XCTestCase {

  func interactive_test_Example() async throws {

    let directorId = JobDirector.ID("2SdMYYK0hxdGouMBjmAGid")!

    let director = try JobDirector(id: directorId,
                                   directory: URL(fileURLWithPath: "/Users/kdubb/Downloads/KubrickTest"),
                                   typeResolver: jobTypeResolver)

    director.injected.provide(URLSessionJobManager(configuration: .background(withIdentifier: directorId.description),
                                                   director: director))
    director.injected.provide(SimpleMessageCipherFactory(), forType: MessageCipherFactory.self)
    director.injected.provide(SimpleMessageSignerFactory(), forType: MessageSignerFactory.self)

    let summary = MessageSummary(sender: .init(address: URL(string: "http://example.com")!, alias: "test"),
                                 attachments: [
                                  "Fast": URL(string: "http://localhost:6789/files/fast")!,
                                  "Medium": URL(string: "http://localhost:6789/files/medium")!,
                                  "Slow": URL(string: "http://localhost:6789/files/slow")!,
                                 ])

    if try await director.start() > 0 {

      print("📤 Jobs reloaded... waiting for completion of jobs")

    }
    else {

      print("📤 Submitting job to director")

      try await director.submit(ProcessMessageJob(summary: summary), id: JobID(string: "32SrLZWr4mC3rvXDlQ8Jem")!)
    }

    try await director.waitForCompletionOfCurrentJobs(timeout: 30 * 60)
  }
}


let jobTypeResolver = TypeNameTypeResolver(jobs: [
  ProcessMessageJob.self
])


struct ProcessMessageJob: SubmittableJob {

  @JobInput var summary: MessageSummary
  @JobInput private var encryption: EncryptionInfo?
  @JobInput private var downloadedAttachments: [String: URL]

  init(summary: MessageSummary) {
    self.summary = summary

    if summary.encryption != nil {
      self.$encryption.bind {
        ValidateMessage(summary: summary)
          .catch { error in
            return nil
          }
      }
    }
    else {
      self.encryption = nil
    }

    self.$downloadedAttachments.bind {
      BatchJob(summary.attachments) { (attachmentId, attachmentURL) in
        URLSessionDownloadFileJob()
          .request(URLRequest(url: attachmentURL))
          .progress { _, currentBytes, totalBytes in
            print("⬇️ Progress for \(attachmentId): current-bytes=\(currentBytes), total-bytes=\(totalBytes)")
          }
          .retry(maxAttempts: 2)
          .map { $0.fileURL }
      }
    }
  }

  func execute() async {
    print("🎉🎉🎉 WE MADE IT 🎉🎉🎉")

    let saveDir = URL(fileURLWithPath: "/Users/kdubb/downloads/KubrickTest")

    for (key, url) in downloadedAttachments {
      let targetFile = saveDir.appendingPathComponent(key).appendingPathExtension("data")
      let urlSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize?.description
      print("🗂️ Saving attachment '\(key)': file=\(targetFile), \(urlSize ?? "unknown")")
      try? FileManager.default.moveItem(at: url, to: targetFile)
    }
  }

  init(from data: Data, using decoder: any JobDecoder) throws {
    let summary = try decoder.decode(MessageSummary.self, from: data)
    self.init(summary: summary)
  }

  func encode(using encoder: any JobEncoder) throws -> Data {
    return try encoder.encode(summary)
  }

}

struct ResolveSenderRouteJob: ResultJob {

  @JobInput var address: URL

  init(address: URL) {
    self.address = address
  }

  func execute() async throws -> ResolvedRoute {
    // Call API to resolve route
    ResolvedRoute()
  }

}


struct ValidateSigningKey: ResultJob {

  @JobInput var resolvedRoute: ResolvedRoute
  
  @JobInject private var securityCache: SecurityCache
  @JobInject private var trustRoots: TrustRoots

  init(address: URL) {
    $resolvedRoute.bind {
      ResolveSenderRouteJob(address: address)
    }
  }

  func execute() async throws -> SecKeyBox {
    guard let encryption = resolvedRoute.encryption else {
      throw MessageProcessingError.unsecuredRoute
    }
    return try await securityCache.publicKey(of: encryption.signingCertificate,
                                             trustedCertificates: trustRoots.certificates)
  }
}


struct ValidateMessage: ResultJob {

  @JobInput var summary: MessageSummary
  @JobInput private var senderSigningKey: SecKeyBox

  @JobInject private var localEncryptionKey: LocalEncryptionKey
  @JobInject private var messageSignerFactory: MessageSignerFactory
  @JobInject private var messageCipherFactory: MessageCipherFactory

  init(summary: MessageSummary) {
    self.summary = summary
    self.$senderSigningKey.bind {
      ValidateSigningKey(address: summary.sender.address)
    }
  }

  func execute() async throws -> EncryptionInfo? {
    guard let encryption = summary.encryption else {
      return nil
    }

    let signer = try messageSignerFactory.signer(for: encryption.signer)
    if try signer.verify(summary: summary, key: senderSigningKey.key) == false {
      throw MessageProcessingError.invalidSignature
    }

    let cipher = try messageCipherFactory.cipher(for: encryption.cipher)
    let key = try cipher.unwrap(wrapped: encryption.key, with: localEncryptionKey.key)

    return EncryptionInfo(key: key, cipher: cipher)
  }

}


struct MessageSummary: Codable, JobHashable {

  struct Encryption: Codable {
    var key: Data
    var signature: Data
    var cipher: MessageCipherVersion
    var signer: MessageSignerVersion
  }

  struct Sender: Hashable, Codable {
    var address: URL
    var alias: String
  }

  var encryption: Encryption?
  var sender: Sender
  var attachments: [String: URL]
}


struct EncryptionInfo: Codable, JobHashable {
  var key: SymmetricKey
  var cipher: MessageCipher

  init(key: SymmetricKey, cipher: MessageCipher) {
    self.key = key
    self.cipher = cipher
  }

  enum CodingKeys: String, CodingKey {
    case key
    case cipher
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.key = SymmetricKey(data: try container.decode(Data.self, forKey: .key))
    self.cipher = try container.decode(MessageCipherVersion.self, forKey: .cipher).cipher
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(key.withUnsafeBytes { Data($0) }, forKey: .key)
    try container.encode(cipher.version, forKey: .cipher)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(key.withUnsafeBytes { Data($0) })
    hasher.combine(cipher.version)
  }

  static func ==(lhs: Self, rhs: Self) -> Bool {
    return lhs.key == rhs.key && lhs.cipher.version == rhs.cipher.version
  }
}


struct ResolvedRoute: Codable, JobHashable {

  struct Encryption: Codable, JobHashable {
    var encryptionCertificate: SecCertificate
    var signingCertificate: SecCertificate

    init(encryptionCertificate: SecCertificate, signingCertificate: SecCertificate) {
      self.encryptionCertificate = encryptionCertificate
      self.signingCertificate = signingCertificate
    }

    enum CodingKeys: CodingKey {
      case encryptionCertificate
      case signingCertificate
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let encryptionCertificateData = try container.decode(Data.self, forKey: .encryptionCertificate)
      self.encryptionCertificate = SecCertificateCreateWithData(nil, encryptionCertificateData as CFData)!
      let signingCertificateData = try container.decode(Data.self, forKey: .signingCertificate)
      self.signingCertificate = SecCertificateCreateWithData(nil, signingCertificateData as CFData)!
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(SecCertificateCopyData(encryptionCertificate) as Data, forKey: .encryptionCertificate)
      try container.encode(SecCertificateCopyData(signingCertificate) as Data, forKey: .signingCertificate)
    }
  }

  var encryption: Encryption?
}


enum MessageProcessingError: Error {
  case invalidSignature
  case unsecuredRoute
}


protocol SecurityCache {

  func publicKey(of cert: SecCertificate, trustedCertificates: [SecCertificate]) async throws -> SecKeyBox

}


struct SimpleSecurityCache: SecurityCache {
  func publicKey(of cert: SecCertificate, trustedCertificates: [SecCertificate]) async throws -> SecKeyBox {
    fatalError()
  }
}


enum MessageCipherVersion: Hashable, Codable {
  case ver1

  var cipher: MessageCipher { fatalError() }
}


protocol MessageCipher {

  var version: MessageCipherVersion { get }

  func unwrap(wrapped key: Data, with unwrappingKey: SecKey) throws -> SymmetricKey
  func decrypt(data: Data, key: SymmetricKey) async throws -> Data

}


protocol MessageCipherFactory {

  func cipher(for: MessageCipherVersion) throws -> any MessageCipher

}


struct SimpleMessageCipherFactory: MessageCipherFactory {
  func cipher(for: MessageCipherVersion) throws -> MessageCipher {
    fatalError()
  }
}


enum MessageSignerVersion: Hashable, Codable {
  case ver1

  var signer: MessageSigner { fatalError() }
}


protocol MessageSigner {

  var version: MessageSignerVersion { get }

  func verify(summary: MessageSummary, key: SecKey) throws -> Bool

}


protocol MessageSignerFactory {

  func signer(for: MessageSignerVersion) throws -> any MessageSigner

}

struct SimpleMessageSignerFactory: MessageSignerFactory {
  func signer(for: MessageSignerVersion) throws -> MessageSigner {
    fatalError()
  }
}

struct TrustRoots {
  var certificates: [SecCertificate]
}

struct LocalEncryptionKey {
  var key: SecKey
}

struct SecKeyBox: Codable, JobHashable {
  var key: SecKey

  init(key: SecKey) {
    self.key = key
  }
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.key = SecKeyCreateWithData(try container.decode(Data.self) as CFData, [:] as CFDictionary, nil)!
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(SecKeyCopyExternalRepresentation(key, nil) as Data?)
  }
}

struct KeyBox: Codable, JobHashable {
  var key: SymmetricKey

  init(key: SymmetricKey) {
    self.key = key
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.key = SymmetricKey(data: try container.decode(Data.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(key.withUnsafeBytes { Data($0) })
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(key.withUnsafeBytes { Data($0) })
  }
}
