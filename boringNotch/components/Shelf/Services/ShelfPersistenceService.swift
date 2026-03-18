//
//  ShelfPersistenceService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import Foundation
import os

// Access model types
@_exported import struct Foundation.URL


final class ShelfPersistenceService {
    private let logger = Logger(subsystem: "com.dynanotch.app", category: "ShelfPersistence")
    static let shared = ShelfPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support: URL
        do {
            support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        } catch {
            logger.warning("Could not access Application Support: \(error.localizedDescription)")
            support = fm.temporaryDirectory
        }
        let dir = support.appendingPathComponent("boringNotch", isDirectory: true).appendingPathComponent("Shelf", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Could not create Shelf directory: \(error.localizedDescription)")
        }
        fileURL = dir.appendingPathComponent("items.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> [ShelfItem] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            logger.info("No shelf data file found or unreadable: \(error.localizedDescription)")
            return []
        }

        // Try to decode as array first (normal case)
        do {
            return try decoder.decode([ShelfItem].self, from: data)
        } catch {
            logger.warning("Array decode failed, attempting item-by-item recovery: \(error.localizedDescription)")
        }
        
        // If array decoding fails, try to decode individual items
        do {
            // Parse as JSON array to get individual item data
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                logger.warning("Shelf persistence file is not a valid JSON array")
                return []
            }
            
            var validItems: [ShelfItem] = []
            var failedCount = 0
            
            for (index, jsonItem) in jsonArray.enumerated() {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonItem)
                    let item = try decoder.decode(ShelfItem.self, from: itemData)
                    validItems.append(item)
                } catch {
                    failedCount += 1
                    logger.warning("Failed to decode shelf item at index \(index): \(error.localizedDescription)")
                }
            }
            
            if failedCount > 0 {
                logger.info("Loaded \(validItems.count) shelf items, discarded \(failedCount) corrupted items")
            }
            
            return validItems
        } catch {
            logger.error("Failed to parse shelf persistence file: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ items: [ShelfItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        } catch {
            logger.error("Failed to save shelf items: \(error.localizedDescription)")
        }
    }
}
