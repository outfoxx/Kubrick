//
//  JobCodec.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCodables
import PotentCBOR


public protocol JobEncoder: TopLevelEncoder where Output == Data {}
public protocol JobDecoder: TopLevelDecoder where Input == Data {}


extension CBOREncoder: JobEncoder {}
extension CBORDecoder: JobDecoder {}
