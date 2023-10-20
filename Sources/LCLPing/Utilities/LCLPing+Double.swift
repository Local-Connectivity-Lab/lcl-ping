//
//  LCLPing+Double.swift
//  
//
//  Created by JOHN ZZN on 10/20/23.
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
