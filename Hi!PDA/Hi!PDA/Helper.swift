//
//  Helper.swift
//  Hi!PDA
//
//  Created by leizh007 on 16/6/9.
//  Copyright © 2016年 Hi!PDA. All rights reserved.
//

import Foundation

func logMessage(message: String, filename: String = #file, line: Int = #line, function: String = #function) {
    #if DEBUG
        print("\((filename as NSString).lastPathComponent):\(line) \(function):\r\(message)")
    #endif
}