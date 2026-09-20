import Foundation

public enum V2AssetInputSource: Sendable {
    case attachment, speech, importedFile
    var moduleID: String {
        switch self {
        case .attachment: "core.attachments"
        case .speech: "core.speech"
        case .importedFile: "core.imports"
        }
    }
}

public extension V2Engine {
    /// Direct ledger entry for the compact amount/description form. This is a
    /// ledger command by itself: it deliberately does not create a Capture
    /// source and therefore remains available when the Capture module/page is
    /// disabled. AI classification may still leave the entry in `others`.
    @discardableResult
    func createManualLedgerEntry(
        amount: String,
        currency: String,
        direction: V2LedgerDirection = .expense,
        text: String,
        localDate: String? = nil,
        categoryID: String = "others",
        categoryConfirmed: Bool = false,
        at date: Date = Date()
    ) throws -> V2LedgerEntry {
        let normalizedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard V2CaptureContract.validAmount(normalizedAmount) else { throw V2CaptureError.invalidAmount }
        guard V2CaptureContract.currencies.contains(normalizedCurrency) else { throw V2CaptureError.unknownCurrency }
        guard !normalizedText.isEmpty, normalizedText.count <= 50_000 else { throw V2CaptureError.missingRequiredField }
        if let localDate {
            guard V2CaptureContract.date(localDate, timeZone: .current) != nil else { throw V2CaptureError.invalidSchema }
        }
        return try commit(modules: ["core.ledger"], commandID: "core.ledger.createPending") { snapshot in
            guard categoryID == "others" || categoryConfirmed else { throw V2CaptureError.confirmationRequired }
            guard categoryID == "others" || snapshot.capture.categories.contains(where: {
                $0.id == categoryID && $0.mergedIntoID == nil
            }) else { throw V2CaptureError.invalidReference }
            let id = UUID().uuidString
            let entry = V2LedgerEntry(
                id: id,
                amount: normalizedAmount,
                currency: normalizedCurrency,
                direction: direction,
                text: normalizedText,
                localDate: localDate,
                categoryID: categoryID,
                recordedAt: date,
                receiptID: "manual:\(id)"
            )
            snapshot.capture.ledger.append(entry)
            return entry
        }
    }

    /// Compatibility spelling used by quick actions and import adapters.
    @discardableResult
    func createLedgerEntry(
        amount: String,
        currency: String,
        direction: V2LedgerDirection = .expense,
        text: String,
        localDate: String? = nil,
        categoryID: String = "others",
        categoryConfirmed: Bool = false,
        at date: Date = Date()
    ) throws -> V2LedgerEntry {
        try createManualLedgerEntry(
            amount: amount,
            currency: currency,
            direction: direction,
            text: text,
            localDate: localDate,
            categoryID: categoryID,
            categoryConfirmed: categoryConfirmed,
            at: date
        )
    }

    @discardableResult
    func saveCaptureAsset(_ data: Data, kind: V2CaptureAsset.Kind, fileExtension: String,
                          store: V2CaptureAssetStore, originalFileName: String? = nil, inputSource: V2AssetInputSource = .attachment) throws -> V2CaptureAsset {
        try moduleRuntime.require([inputSource.moduleID])
        guard data.count <= 30 * 1024 * 1024 else { throw V2CaptureError.assetUnavailable }
        var asset = try store.save(data, kind: kind, fileExtension: fileExtension)
        asset.originalFileName = originalFileName.map { String(($0 as NSString).lastPathComponent.prefix(255)) }
        _ = try store.data(for: asset)
        let commandID: String = {
            switch inputSource {
            case .attachment: "core.attachments.save"
            case .speech: "core.speech.save"
            case .importedFile: "core.imports.saveAsset"
            }
        }()
        return try commit(modules: [inputSource.moduleID], commandID: commandID) { snapshot in snapshot.capture.assets.append(asset); return asset }
    }

    @discardableResult
    func saveCapture(text: String, id: String? = nil, expectedRevision: Int? = nil, newSourceID: String? = nil,
                     mediaBlocks: [V2CaptureBlock]? = nil, at date: Date = Date(),
                     timeZone: TimeZone = .current) throws -> V2CaptureEntry {
        try commit(modules: ["core.capture"], commandID: "core.capture.create") { snapshot in
            guard snapshot.capture.schemaVersion == 1 else { throw V2CaptureError.invalidSchema }
            if let newSourceID {
                guard id == nil, !newSourceID.isEmpty, newSourceID.count <= 512 else { throw V2CaptureError.invalidReference }
                if let existing = snapshot.capture.latestEntries.first(where: { $0.id == newSourceID }) {
                    guard existing.text == text, (mediaBlocks ?? []).isEmpty, existing.blocks.allSatisfy({ $0.kind == .text }) else { throw V2CaptureError.staleSource }
                    return existing
                }
            }
            let prior = id.flatMap { id in snapshot.capture.latestEntries.first { $0.id == id } }
            let mediaBlocks = mediaBlocks ?? prior?.blocks.filter { $0.kind != .text } ?? []
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaBlocks.isEmpty else { throw V2CaptureError.missingRequiredField }
            guard text.count <= 50_000, mediaBlocks.count <= 20,
                  mediaBlocks.allSatisfy({ $0.kind != .text && $0.assetID != nil }) else { throw V2CaptureError.invalidSchema }
            guard mediaBlocks.allSatisfy({ block in snapshot.capture.assets.contains { $0.id == block.assetID && $0.kind.rawValue == block.kind.rawValue } }) else { throw V2CaptureError.assetUnavailable }
            guard Set(mediaBlocks.map(\.id)).count == mediaBlocks.count else { throw V2CaptureError.invalidSchema }
            if id != nil, prior == nil { throw V2CaptureError.invalidReference }
            if let prior, expectedRevision != prior.revision { throw V2CaptureError.staleSource }
            let block = V2CaptureBlock(id: prior?.blocks.first(where: { $0.kind == .text })?.id ?? UUID().uuidString, text: text)
            let blocks = [block] + mediaBlocks
            if let prior, prior.blocks == blocks { return prior }
            let entry = V2CaptureEntry(id: id ?? newSourceID ?? UUID().uuidString, revision: (prior?.revision ?? 0) + 1,
                recordedAt: date, timeZoneIdentifier: prior?.timeZoneIdentifier ?? timeZone.identifier, blocks: blocks)
            snapshot.capture.entries.append(entry)
            return entry
        }
    }

    @discardableResult
    func stageCaptureProposal(_ proposal: V2CaptureProposal, model: String, traceID: String = UUID().uuidString,
                              at date: Date = Date()) throws -> V2CaptureBatch {
        // The manual and AI routes have exactly the same structural boundary.
        _ = try V2CaptureContract.decode(JSONEncoder().encode(proposal))
        return try commit(modules: ["core.capture"], commandID: "core.capture.stage") { snapshot in
            guard let source = snapshot.capture.latestEntries.first(where: { $0.id == proposal.captureID }),
                  source.revision == proposal.sourceRevision else { throw V2CaptureError.staleSource }
            guard !proposal.items.isEmpty, proposal.items.count <= 50,
                  Set(proposal.items.map(\.candidateID)).count == proposal.items.count,
                  proposal.items.allSatisfy({ !$0.candidateID.isEmpty && $0.candidateID.count <= 100 }) else { throw V2CaptureError.invalidSchema }
            if snapshot.capture.imports?.contains(where: { $0.reviewOnlyCaptureIDs?.contains(source.id) == true }) == true,
               proposal.items.contains(where: { $0.kind == .task }) { throw V2CaptureError.invalidSchema }
            if let existing = snapshot.capture.batches.last(where: { batch in
                batch.proposal == proposal && !snapshot.capture.receipts.contains { $0.batchID == batch.id && $0.status == .undone }
            }) { return existing }
            let batch = V2CaptureBatch(id: UUID().uuidString, traceID: traceID, proposal: proposal,
                model: model, taxonomyRevision: snapshot.capture.taxonomyRevision, createdAt: date)
            snapshot.capture.batches.append(batch)
            return batch
        }
    }

    /// Apply a user's typed correction to a staged ledger candidate. The
    /// source revision and candidate ID are immutable. The original proposal
    /// remains untouched; the latest typed values live in a candidate-scoped
    /// override and every changed field is appended to the correction log.
    /// Incomplete values are retained as a needs-information candidate and
    /// are rejected later by the normal apply validation.
    @discardableResult
    func reviseLedgerCandidate(
        batchID: String,
        candidateID: String,
        sourceRevision: Int,
        draft: V2LedgerCandidateDraft,
        at date: Date = Date()
    ) throws -> V2CaptureCandidate {
        try commit(modules: ["core.capture"], commandID: "core.capture.reviseCandidate") { snapshot in
            guard let batchIndex = snapshot.capture.batches.firstIndex(where: { $0.id == batchID }),
                  let original = snapshot.capture.batches[batchIndex].proposal.items.first(where: { $0.candidateID == candidateID }),
                  let source = snapshot.capture.latestEntries.first(where: {
                      $0.id == snapshot.capture.batches[batchIndex].proposal.captureID
                  }),
                  sourceRevision == snapshot.capture.batches[batchIndex].proposal.sourceRevision,
                  source.revision == snapshot.capture.batches[batchIndex].proposal.sourceRevision else {
                throw V2CaptureError.staleSource
            }
            let previousReceipt = snapshot.capture.receipts.last(where: {
                $0.batchID == batchID && $0.candidateID == candidateID
            })
            guard original.kind == .ledger || original.kind == .other else {
                throw V2CaptureError.invalidSchema
            }
            guard previousReceipt?.status != .rejected && previousReceipt?.status != .undone else {
                throw V2CaptureError.staleTarget
            }
            guard previousReceipt?.targetID == nil else { throw V2CaptureError.staleTarget }
            let normalized = try Self.normalizedLedgerDraft(draft, source: source)
            let old = snapshot.capture.batches[batchIndex].effectiveCandidate(for: candidateID) ?? original
            let next = Self.ledgerCandidate(from: original, draft: normalized)
            guard old != next else { return old }

            Self.recordLedgerOverride(
                normalized,
                for: candidateID,
                original: original,
                old: old,
                next: next,
                in: &snapshot.capture.batches[batchIndex],
                at: date
            )
            return next
        }
    }

    /// Confirm the current typed values and create the ledger row in one
    /// cross-module commit. This is the dedicated ledger path: it never
    /// silently classifies a row and it leaves the original proposal intact.
    @discardableResult
    func confirmLedgerCandidate(
        batchID: String,
        candidateID: String,
        sourceRevision: Int,
        draft: V2LedgerCandidateDraft,
        at date: Date = Date()
    ) throws -> V2CaptureReceipt {
        try moduleRuntime.require(["core.capture", "core.ledger"])
        if let existing = snapshot.capture.receipts.last(where: {
            $0.batchID == batchID && $0.candidateID == candidateID
        }), existing.targetID != nil || existing.status == .rejected || existing.status == .undone {
            return existing
        }
        return try commit(modules: ["core.capture", "core.ledger"], commandID: "core.capture.confirmLedgerCandidate") { snapshot in
            guard let batchIndex = snapshot.capture.batches.firstIndex(where: { $0.id == batchID }),
                  let original = snapshot.capture.batches[batchIndex].proposal.items.first(where: { $0.candidateID == candidateID }),
                  let source = snapshot.capture.latestEntries.first(where: {
                      $0.id == snapshot.capture.batches[batchIndex].proposal.captureID
                  }),
                  sourceRevision == snapshot.capture.batches[batchIndex].proposal.sourceRevision,
                  source.revision == snapshot.capture.batches[batchIndex].proposal.sourceRevision else {
                throw V2CaptureError.staleSource
            }
            let previousReceipt = snapshot.capture.receipts.last(where: {
                $0.batchID == batchID && $0.candidateID == candidateID
            })
            guard original.kind == .ledger || original.kind == .other else {
                throw V2CaptureError.invalidSchema
            }
            if let previousReceipt, previousReceipt.status == .rejected || previousReceipt.status == .undone {
                return previousReceipt
            }
            guard previousReceipt?.targetID == nil else {
                return previousReceipt!
            }

            let otherBatches = Set(snapshot.capture.batches.filter {
                $0.id != batchID && $0.proposal.captureID == source.id
            }.map(\.id))
            guard !snapshot.capture.receipts.contains(where: {
                otherBatches.contains($0.batchID)
                    && ($0.status == .applied || $0.status == .needsConfirmation)
                    && $0.targetID != nil
            }) else { throw V2CaptureError.duplicateCandidate }

            let normalized = try Self.normalizedLedgerDraft(draft, source: source)
            let old = snapshot.capture.batches[batchIndex].effectiveCandidate(for: candidateID) ?? original
            let next = Self.ledgerCandidate(from: original, draft: normalized)
            try V2CaptureContract.validate(next, source: source)
            Self.recordLedgerOverride(
                normalized,
                for: candidateID,
                original: original,
                old: old,
                next: next,
                in: &snapshot.capture.batches[batchIndex],
                at: date
            )

            let reusableReceiptIndex = snapshot.capture.receipts.lastIndex {
                $0.batchID == batchID && $0.candidateID == candidateID && $0.targetID == nil
                    && ($0.status == .needsInformation || $0.status == .failed)
            }
            let reusableReceipt = reusableReceiptIndex.map { snapshot.capture.receipts[$0] }
            var receipt = V2CaptureReceipt(
                id: reusableReceipt?.id ?? UUID().uuidString,
                batchID: batchID,
                candidateID: candidateID,
                status: .needsConfirmation,
                createdAt: reusableReceipt?.createdAt ?? date
            )
            receipt.resolvedEvidence = try V2CaptureContract.resolveEvidence(next, source: source)
            let payload = next.payload
            let entry = V2LedgerEntry(
                id: UUID().uuidString,
                amount: payload.amount!,
                currency: payload.currency!,
                direction: payload.direction!,
                text: payload.text,
                localDate: payload.localDate,
                recordedAt: date,
                receiptID: receipt.id
            )
            snapshot.capture.ledger.append(entry)
            receipt.ledgerAfter = entry
            receipt.targetID = entry.id
            if let reusableReceiptIndex { snapshot.capture.receipts[reusableReceiptIndex] = receipt }
            else { snapshot.capture.receipts.append(receipt) }
            return receipt
        }
    }

    @discardableResult
    func applyCaptureCandidate(batchID: String, candidateID: String, at date: Date = Date()) throws -> V2CaptureReceipt {
        try moduleRuntime.require(["core.capture"])
        if let existing = snapshot.capture.receipts.last(where: { $0.batchID == batchID && $0.candidateID == candidateID }),
           existing.targetID != nil || existing.status == .applied || existing.status == .needsConfirmation
               || existing.status == .rejected || existing.status == .undone {
            return existing
        }
        return try commit(modules: ["core.capture"], commandID: "core.capture.apply") { snapshot in
            guard let batch = snapshot.capture.batches.first(where: { $0.id == batchID }),
                  let item = batch.effectiveCandidate(for: candidateID),
                  let source = snapshot.capture.latestEntries.first(where: { $0.id == batch.proposal.captureID })
            else { throw V2CaptureError.invalidReference }
            guard source.revision == batch.proposal.sourceRevision else { throw V2CaptureError.staleSource }
            let otherBatches = Set(snapshot.capture.batches.filter { $0.id != batchID && $0.proposal.captureID == source.id }.map(\.id))
            guard !snapshot.capture.receipts.contains(where: {
                otherBatches.contains($0.batchID) && ($0.status == .applied || $0.status == .needsConfirmation) && $0.targetID != nil
            }) else { throw V2CaptureError.duplicateCandidate }
            let reusableReceiptIndex = snapshot.capture.receipts.lastIndex(where: {
                $0.batchID == batchID && $0.candidateID == candidateID && $0.targetID == nil
                    && ($0.status == .needsInformation || $0.status == .failed)
            })
            var receipt = reusableReceiptIndex.map { snapshot.capture.receipts[$0] }
                ?? V2CaptureReceipt(id: UUID().uuidString, batchID: batchID, candidateID: candidateID,
                    status: .applied, createdAt: date)
            receipt.status = .applied
            receipt.error = nil
            receipt.targetID = nil
            receipt.ledgerAfter = nil
            receipt.recallBefore = nil
            receipt.recallAfter = nil
            receipt.noteAfter = nil
            receipt.scheduleReceiptID = nil
            receipt.resolvedEvidence = nil
            do { try V2CaptureContract.validate(item, source: source) }
            catch {
                receipt.status = .needsInformation; receipt.error = error as? V2CaptureError ?? .invalidSchema
                if let reusableReceiptIndex { snapshot.capture.receipts[reusableReceiptIndex] = receipt }
                else { snapshot.capture.receipts.append(receipt) }
                return receipt
            }
            receipt.resolvedEvidence = try V2CaptureContract.resolveEvidence(item, source: source)
            try moduleRuntime.require([Self.module(for: item.kind)])
            let payload = item.payload
            switch item.kind {
            case .ledger:
                let entry = V2LedgerEntry(id: UUID().uuidString, amount: payload.amount!, currency: payload.currency!,
                    direction: payload.direction!, text: payload.text, localDate: payload.localDate,
                    recordedAt: date, receiptID: receipt.id)
                snapshot.capture.ledger.append(entry)
                receipt.ledgerAfter = entry; receipt.targetID = entry.id; receipt.status = .needsConfirmation
            case .recall:
                let zone = TimeZone(identifier: source.timeZoneIdentifier) ?? .current
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                let day = V2CaptureContract.date(payload.localDate!, timeZone: zone)!
                let index = snapshot.recallEntries.indices.filter { calendar.isDate(snapshot.recallEntries[$0].date, inSameDayAs: day) }
                    .max { snapshot.recallEntries[$0].updatedAt < snapshot.recallEntries[$1].updatedAt }
                if let index {
                    receipt.recallBefore = snapshot.recallEntries[index]
                    snapshot.recallEntries[index].text += (snapshot.recallEntries[index].text.isEmpty ? "" : "\n\n") + payload.text
                    snapshot.recallEntries[index].updatedAt = date
                    receipt.recallAfter = snapshot.recallEntries[index]
                } else {
                    let entry = V2RecallEntry(id: UUID().uuidString, date: day, text: payload.text,
                        hasHandwriting: false, referencedTaskIDs: [], referencedSegmentIDs: [], referencedPlanItemIDs: [], createdAt: date, updatedAt: date)
                    snapshot.recallEntries.append(entry); receipt.recallAfter = entry
                }
                receipt.targetID = receipt.recallAfter?.id
            case .task:
                // Reuse the schedule domain command on a staged snapshot. Persistence and the capture receipt
                // commit together, so a crash cannot leave an unlinked task or duplicate it on retry.
                let staged = V2Engine(snapshot: snapshot, moduleRuntime: moduleRuntime)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: source.timeZoneIdentifier) ?? .current
                do {
                    let schedule = try staged.applyScheduleProposal(.init(summary: payload.text, operations: payload.operations!),
                        requestID: "capture:\(batchID):\(candidateID)", at: date, calendar: calendar)
                    snapshot = staged.snapshot
                    receipt.scheduleReceiptID = schedule.id
                    receipt.targetID = schedule.changes.first?.entityID
                } catch {
                    receipt.status = .failed; receipt.error = .invalidReference
                }
            case .inspiration, .futureIdea, .other:
                let note = V2CaptureNote(id: UUID().uuidString, kind: item.kind, title: payload.title,
                    text: payload.text, receiptID: receipt.id, recordedAt: date)
                snapshot.capture.notes.append(note); receipt.noteAfter = note; receipt.targetID = note.id
                if item.kind == .other { receipt.status = .needsInformation }
            }
            if let reusableReceiptIndex { snapshot.capture.receipts[reusableReceiptIndex] = receipt }
            else { snapshot.capture.receipts.append(receipt) }
            return receipt
        }
    }

    /// A re-analysis is a preview until explicitly accepted. All target preconditions are checked
    /// on a staged snapshot; later manual edits prevent replacement of the whole batch.
    func replaceCaptureResults(batchID: String, confirmed: Bool, at date: Date = Date()) throws {
        guard confirmed else { throw V2CaptureError.confirmationRequired }
        try commit(modules: ["core.capture"], commandID: "core.capture.replace") { snapshot in
            guard let batch = snapshot.capture.batches.first(where: { $0.id == batchID }),
                  let source = snapshot.capture.latestEntries.first(where: { $0.id == batch.proposal.captureID }),
                  source.revision == batch.proposal.sourceRevision else { throw V2CaptureError.staleSource }
            guard !snapshot.capture.receipts.contains(where: { $0.batchID == batchID }) else { throw V2CaptureError.staleTarget }
            for item in batch.proposal.items {
                try V2CaptureContract.validate(batch.effectiveCandidate(for: item.id) ?? item, source: source)
            }
            let oldIDs = Set(snapshot.capture.batches.filter { $0.id != batchID && $0.proposal.captureID == source.id }.map(\.id))
            let staged = V2Engine(snapshot: snapshot, moduleRuntime: moduleRuntime)
            for receipt in snapshot.capture.receipts.reversed() where oldIDs.contains(receipt.batchID)
                && receipt.status != .undone && receipt.status != .rejected {
                try staged.undoCaptureReceipt(id: receipt.id, at: date)
            }
            for item in batch.proposal.items {
                let receipt = try staged.applyCaptureCandidate(batchID: batchID, candidateID: item.id, at: date)
                guard receipt.status != .failed, receipt.error == nil else { throw receipt.error ?? V2CaptureError.invalidSchema }
            }
            snapshot = staged.snapshot
        }
    }

    func rejectCaptureCandidate(batchID: String, candidateID: String, at date: Date = Date()) throws {
        try commit(modules: ["core.capture"], commandID: "core.capture.reject") { snapshot in
            guard snapshot.capture.batches.contains(where: { $0.id == batchID && $0.proposal.items.contains(where: { $0.candidateID == candidateID }) }),
                  !snapshot.capture.receipts.contains(where: { $0.batchID == batchID && $0.candidateID == candidateID }) else { throw V2CaptureError.staleTarget }
            snapshot.capture.receipts.append(.init(id: UUID().uuidString, batchID: batchID, candidateID: candidateID, status: .rejected, createdAt: date))
        }
    }

    func undoCaptureReceipt(id: String, at date: Date = Date()) throws {
        try commit(modules: ["core.capture"], commandID: "core.capture.undo") { snapshot in
            guard let index = snapshot.capture.receipts.firstIndex(where: { $0.id == id }) else { throw V2CaptureError.invalidReference }
            let receipt = snapshot.capture.receipts[index]
            guard receipt.status != .undone && receipt.status != .rejected else { throw V2CaptureError.staleTarget }
            if let after = receipt.ledgerAfter {
                try moduleRuntime.require(["core.ledger"])
                guard snapshot.capture.ledger.first(where: { $0.id == after.id }) == after else { throw V2CaptureError.staleTarget }
                snapshot.capture.ledger.removeAll { $0.id == after.id }
            }
            if let after = receipt.recallAfter {
                try moduleRuntime.require(["core.recall"])
                guard let target = snapshot.recallEntries.firstIndex(where: { $0.id == after.id }), snapshot.recallEntries[target] == after else { throw V2CaptureError.staleTarget }
                if let before = receipt.recallBefore { snapshot.recallEntries[target] = before }
                else { snapshot.recallEntries.remove(at: target) }
            }
            if let note = receipt.noteAfter {
                try moduleRuntime.require(["core.notes"])
                guard snapshot.capture.notes.first(where: { $0.id == note.id }) == note else { throw V2CaptureError.staleTarget }
                snapshot.capture.notes.removeAll { $0.id == note.id }
            }
            if let scheduleID = receipt.scheduleReceiptID {
                let staged = V2Engine(snapshot: snapshot, moduleRuntime: moduleRuntime)
                _ = try staged.undoScheduleReceipt(id: scheduleID, at: date)
                snapshot = staged.snapshot
            }
            snapshot.capture.receipts[index].status = .undone
        }
    }

    @discardableResult
    func createLedgerCategory(name: String, parentID: String? = nil, confirmed: Bool) throws -> V2LedgerCategory {
        guard confirmed else { throw V2CaptureError.confirmationRequired }
        return try commit(modules: ["core.ledger"], commandID: "core.ledger.createCategory") { snapshot in
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 40 else { throw V2CaptureError.missingRequiredField }
            if let parentID {
                guard parentID != "others", snapshot.capture.categories.contains(where: { $0.id == parentID && $0.mergedIntoID == nil }) else { throw V2CaptureError.invalidReference }
            }
            guard !snapshot.capture.categories.contains(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame && $0.mergedIntoID == nil }) else { throw V2CaptureError.duplicateCandidate }
            let category = V2LedgerCategory(id: UUID().uuidString, name: normalized, parentID: parentID)
            snapshot.capture.categories.append(category); snapshot.capture.taxonomyRevision += 1
            return category
        }
    }

    func confirmLedgerCategory(ledgerID: String, categoryName: String, expectedRevision: Int, confirmed: Bool) throws {
        guard confirmed else { throw V2CaptureError.confirmationRequired }
        try commit(modules: ["core.ledger"], commandID: "core.ledger.confirmCategory") { snapshot in
            guard let index = snapshot.capture.ledger.firstIndex(where: { $0.id == ledgerID }) else { throw V2CaptureError.invalidReference }
            guard snapshot.capture.ledger[index].revision == expectedRevision else { throw V2CaptureError.staleTarget }
            let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 40 else { throw V2CaptureError.missingRequiredField }
            let before = snapshot.capture
            let category: V2LedgerCategory
            if let existing = snapshot.capture.categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.mergedIntoID == nil }) { category = existing }
            else {
                category = .init(id: UUID().uuidString, name: name)
                snapshot.capture.categories.append(category)
            }
            snapshot.capture.ledger[index].categoryID = category.id
            snapshot.capture.ledger[index].revision += 1
            snapshot.capture.taxonomyRevision += 1
            snapshot.capture.categoryReceipts.append(.init(id: UUID().uuidString, beforeCategories: before.categories,
                afterCategories: snapshot.capture.categories, beforeLedger: [before.ledger[index]],
                afterLedger: [snapshot.capture.ledger[index]], taxonomyRevision: snapshot.capture.taxonomyRevision))
            // Business receipt records confirmed disposition, but retains original before/after for conflict-safe undo.
            if let receiptIndex = snapshot.capture.receipts.firstIndex(where: { $0.id == snapshot.capture.ledger[index].receiptID }) {
                snapshot.capture.receipts[receiptIndex].status = .applied
                snapshot.capture.receipts[receiptIndex].ledgerAfter = snapshot.capture.ledger[index]
            }
        }
    }

    @discardableResult
    func mergeLedgerCategories(sourceID: String, targetID: String, expectedTaxonomyRevision: Int,
                               confirmed: Bool) throws -> V2CategoryReceipt {
        guard confirmed else { throw V2CaptureError.confirmationRequired }
        return try commit(modules: ["core.ledger"], commandID: "core.ledger.mergeCategories") { snapshot in
            guard snapshot.capture.taxonomyRevision == expectedTaxonomyRevision else { throw V2CaptureError.staleTarget }
            guard sourceID != targetID, sourceID != "others", targetID != "others",
                  let source = snapshot.capture.categories.firstIndex(where: { $0.id == sourceID && $0.mergedIntoID == nil }),
                  snapshot.capture.categories.contains(where: { $0.id == targetID && $0.mergedIntoID == nil }) else { throw V2CaptureError.invalidReference }
            var cursor: String? = targetID
            while let id = cursor {
                guard id != sourceID else { throw V2CaptureError.invalidReference }
                cursor = snapshot.capture.categories.first { $0.id == id }?.parentID
            }
            let before = snapshot.capture
            snapshot.capture.categories[source].mergedIntoID = targetID
            for i in snapshot.capture.categories.indices where snapshot.capture.categories[i].parentID == sourceID {
                snapshot.capture.categories[i].parentID = targetID
            }
            for i in snapshot.capture.ledger.indices where snapshot.capture.ledger[i].categoryID == sourceID {
                snapshot.capture.ledger[i].categoryID = targetID; snapshot.capture.ledger[i].revision += 1
            }
            snapshot.capture.taxonomyRevision += 1
            let changed = Set(before.ledger.filter { $0.categoryID == sourceID }.map(\.id))
            let receipt = V2CategoryReceipt(id: UUID().uuidString, beforeCategories: before.categories,
                afterCategories: snapshot.capture.categories, beforeLedger: before.ledger.filter { changed.contains($0.id) },
                afterLedger: snapshot.capture.ledger.filter { changed.contains($0.id) }, taxonomyRevision: snapshot.capture.taxonomyRevision)
            snapshot.capture.categoryReceipts.append(receipt)
            return receipt
        }
    }

    func undoCategoryReceipt(id: String) throws {
        try commit(modules: ["core.ledger"], commandID: "core.ledger.undoCategory") { snapshot in
            guard let index = snapshot.capture.categoryReceipts.firstIndex(where: { $0.id == id }) else { throw V2CaptureError.invalidReference }
            let receipt = snapshot.capture.categoryReceipts[index]
            guard !receipt.undone, snapshot.capture.taxonomyRevision == receipt.taxonomyRevision,
                  snapshot.capture.categories == receipt.afterCategories,
                  receipt.afterLedger.allSatisfy({ row in snapshot.capture.ledger.first { $0.id == row.id } == row }) else { throw V2CaptureError.staleTarget }
            let removedCategoryIDs = Set(receipt.afterCategories.map(\.id)).subtracting(receipt.beforeCategories.map(\.id))
            let affectedIDs = Set(receipt.afterLedger.map(\.id))
            guard !snapshot.capture.ledger.contains(where: { !affectedIDs.contains($0.id) && removedCategoryIDs.contains($0.categoryID) }) else { throw V2CaptureError.staleTarget }
            snapshot.capture.categories = receipt.beforeCategories
            for row in receipt.beforeLedger {
                if let i = snapshot.capture.ledger.firstIndex(where: { $0.id == row.id }) { snapshot.capture.ledger[i] = row }
                if let i = snapshot.capture.receipts.firstIndex(where: { $0.id == row.receiptID }) {
                    snapshot.capture.receipts[i].status = row.categoryID == "others" ? .needsConfirmation : .applied
                    snapshot.capture.receipts[i].ledgerAfter = row
                }
            }
            snapshot.capture.taxonomyRevision += 1
            snapshot.capture.categoryReceipts[index].undone = true
        }
    }
}

private extension V2Engine {
    static func normalizedLedgerDraft(
        _ draft: V2LedgerCandidateDraft,
        source: V2CaptureEntry
    ) throws -> V2LedgerCandidateDraft {
        guard draft.kind == .ledger else { throw V2CaptureError.invalidSchema }
        func optionalTrimmed(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 50_000 else { throw V2CaptureError.missingRequiredField }
        let amount = optionalTrimmed(draft.amount)
        if let amount, !V2CaptureContract.validAmount(amount) { throw V2CaptureError.invalidAmount }
        let currency = optionalTrimmed(draft.currency)?.uppercased()
        if let currency, !V2CaptureContract.currencies.contains(currency) { throw V2CaptureError.unknownCurrency }
        let localDate = optionalTrimmed(draft.localDate)
        if let localDate {
            guard V2CaptureContract.date(
                localDate,
                timeZone: TimeZone(identifier: source.timeZoneIdentifier) ?? .current
            ) != nil else { throw V2CaptureError.invalidSchema }
        }
        return .init(
            text: text,
            amount: amount,
            currency: currency,
            direction: draft.direction,
            localDate: localDate,
            categoryName: optionalTrimmed(draft.categoryName)
        )
    }

    static func ledgerCandidate(
        from original: V2CaptureCandidate,
        draft: V2LedgerCandidateDraft
    ) -> V2CaptureCandidate {
        V2CaptureCandidate(
            candidateID: original.candidateID,
            kind: draft.kind,
            evidence: original.evidence,
            payload: .init(
                text: draft.text,
                amount: draft.amount,
                currency: draft.currency,
                direction: draft.direction,
                categoryName: draft.categoryName,
                localDate: draft.localDate
            )
        )
    }

    static func recordLedgerOverride(
        _ draft: V2LedgerCandidateDraft,
        for candidateID: String,
        original: V2CaptureCandidate,
        old: V2CaptureCandidate,
        next: V2CaptureCandidate,
        in batch: inout V2CaptureBatch,
        at date: Date
    ) {
        func raw(_ value: String?) -> String? { value }
        let changes: [(V2CaptureCorrectionField, String?, String?)] = [
            (.kind, old.kind.rawValue, next.kind.rawValue),
            (.text, old.payload.text, next.payload.text),
            (.amount, raw(old.payload.amount), raw(next.payload.amount)),
            (.currency, raw(old.payload.currency), raw(next.payload.currency)),
            (.direction, old.payload.direction?.rawValue, next.payload.direction?.rawValue),
            (.localDate, raw(old.payload.localDate), raw(next.payload.localDate)),
            (.categoryName, raw(old.payload.categoryName), raw(next.payload.categoryName))
        ]
        batch.ledgerCandidateOverrides.removeAll { $0.candidateID == candidateID }
        if next != original {
            batch.ledgerCandidateOverrides.append(.init(candidateID: candidateID, draft: draft, at: date))
        }
        for (field, before, after) in changes where before != after {
            batch.corrections.append(
                .init(candidateID: candidateID, field: field, before: before, after: after, at: date)
            )
        }
    }

    static func module(for kind: V2CaptureKind) -> String {
        switch kind {
        case .task: "core.tasks"
        case .ledger: "core.ledger"
        case .recall: "core.recall"
        case .inspiration, .futureIdea, .other: "core.notes"
        }
    }
}
