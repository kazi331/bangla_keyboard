import Foundation
import BanglaEngine
import BanglaStorage

/// The heart of the IME: ties together transliteration, ranking, storage.
/// Runs on a background actor so it never blocks the main thread.
public actor IMEEngine {
    public let layouts: [Layout]
    public let scoringPipeline: ScoringPipeline
    public let lexiconRepo: LexiconRepository?
    public let userRepo: UserRepository?
    public let sessionRepo: SessionRepository?
    public let lm: NGramLanguageModel

    public init(
        layouts: [Layout],
        lexiconRepo: LexiconRepository? = nil,
        userRepo: UserRepository? = nil,
        sessionRepo: SessionRepository? = nil,
        pipeline: ScoringPipeline = ScoringPipeline()
    ) {
        self.layouts = layouts
        self.lexiconRepo = lexiconRepo
        self.userRepo = userRepo
        self.sessionRepo = sessionRepo
        self.scoringPipeline = pipeline
        self.lm = NGramLanguageModel()
    }

    public func layout(for id: String) -> Layout? {
        layouts.first { $0.id == id }
    }

    public func transliterate(latin: String, layoutId: String) -> PhoneticResolver.Resolution? {
        guard let layout = layout(for: layoutId), layout.kind == .phonetic else { return nil }
        return PhoneticResolver(layout: layout).resolve(latin)
    }

    public func fixedMapping(for keystroke: String, layoutId: String) -> String? {
        guard let layout = layout(for: layoutId), layout.kind == .fixed else { return nil }
        let adapter = LayoutAdapter(layout: layout)
        switch adapter.process(keystroke: keystroke) {
        case .literal(let s): return s
        default: return nil
        }
    }

    public func rank(
        latin: String,
        banglaPrefix: String,
        layoutId: String,
        context: [String]
    ) async -> CandidateList {
        var lex: [Candidate] = []
        var usr: [Candidate] = []
        var lmSugg: [Candidate] = []

        if let repo = lexiconRepo {
            lex = (try? repo.candidates(latin: latin, layoutId: layoutId, limit: 256)) ?? []
        }
        if let repo = userRepo {
            usr = (try? repo.userWordCandidates(latin: latin, limit: 128)) ?? []
            lmSugg = (try? repo.ngramSuggestions(context: context, prefix: banglaPrefix, limit: 64)) ?? []
        }

        var editDist: [Candidate] = []
        if lex.count + usr.count < 8 {
            // Use lexicon entries as edit-distance candidates against the latin query.
            editDist = lex.prefix(16).map { c in
                var n = c
                n.source = .editdist
                let scorer = EditDistanceScorer(maxThreshold: max(1, latin.count / 4))
                n.score = scorer.score(latin, against: c.latinHint)
                return n
            }.filter { $0.score > 0 }
        }

        let inputs = ScoringPipeline.Inputs(
            latinQuery: latin,
            banglaPrefix: banglaPrefix,
            context: context,
            appPrior: 0,
            lexicon: lex,
            user: usr,
            lm: lmSugg,
            editDistance: editDist
        )
        return scoringPipeline.rank(inputs)
    }

    public func observeCommit(latin: String, chosen: Candidate, context: [String], sessionId: UUID, appBundleHash: String?) async {
        if let repo = userRepo {
            try? repo.upsertUserWord(bangla: chosen.bangla, latinHint: latin)
            try? repo.recordCommit(
                sessionId: sessionId.uuidString,
                typedLatin: latin,
                chosenBangla: chosen.bangla,
                chosenRank: 0,
                chosenSource: chosen.source.rawValue,
                appBundleHash: appBundleHash
            )
            try? repo.observeNgram(context: context, token: chosen.bangla)
        }
        await lm.observe(context: context, token: chosen.bangla)
    }
}