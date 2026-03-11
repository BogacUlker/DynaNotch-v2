//
//  DebugPrint.swift
//  boringNotch
//
//  Silence all print() calls in Release builds.
//  This module-level function shadows Swift's global print(),
//  so no changes are needed at any call site.
//

#if !DEBUG
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // No-op in release builds
}
#endif
