//
// This source file is part of the LCLPing open source project
//
// Copyright (c) 2021-2023 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation


extension Double {
    
    /**
     Round the double number to given decimal digits
     
     - Precondition: digit has to be >= 0
     - Parameters:
        - to: the number of decimal digits to round to
     - Returns: the value, rounded to the given digits
     */
    func round(to: Int) -> Double {
        let divisor = pow(10.0, Double(to))
        return (self * divisor).rounded() / divisor
    }
}
