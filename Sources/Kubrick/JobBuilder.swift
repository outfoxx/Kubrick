//
//  JobBuilder.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


@resultBuilder
public struct JobBuilder<Result> {

  public static func buildExpression<RJ: Job<Result>>(_ expression: RJ) -> RJ {
    expression
  }

  public static func buildBlock<RJ: Job<Result>>(_ components: RJ...) -> [RJ] {
    return components
  }

  public static func buildArray<RJ: Job<Result>>(_ components: [[RJ]]) -> [RJ] {
    components.flatMap { $0 }
  }

  public static func buildBlock<RJ: Job<Result>>(_ components: RJ) -> RJ {
    return components
  }

  public static func buildArray<RJ: Job<Result>>(_ components: RJ) -> [RJ] {
    [components]
  }

}
