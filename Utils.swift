//
//  Utils.swift
//  SwiftConnect
//
//  Created by Shankar Giri Venkita Giri on 30/06/22.
//

import SwiftUI

func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}
