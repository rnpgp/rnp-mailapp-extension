//
//  Result.swift
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 13.04.2022.
//

import Foundation

extension Result where Success == Void {
    public static func success() -> Self { .success(()) }
}
