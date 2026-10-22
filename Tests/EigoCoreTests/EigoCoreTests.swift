import Foundation
import Testing
@testable import EigoCore

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite struct AnswerCheckerTests {
    @Test func normalizesCaseAndPunctuation() {
        #expect(AnswerChecker.isCorrect("  I Have Never Seen it! ", answers: ["I have never seen it."]))
        #expect(AnswerChecker.isCorrect("can’t", answers: ["cannot"]))
        #expect(AnswerChecker.isCorrect("I don't know", answers: ["I do not know"]))
        #expect(!AnswerChecker.isCorrect("", answers: [""]))
        #expect(!AnswerChecker.isCorrect("have known", answers: ["knew"]))
    }

    @Test func countsWords() {
        #expect(AnswerChecker.wordCount("I think, therefore I am.\n- Descartes") == 6)
    }
}

@Suite struct SchedulerTests {
    @Test func intervalsGrowWhenCorrect() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var c = Scheduler.review(nil, grade: .good, now: now)
        #expect(c.intervalDays == 1)
        c = Scheduler.review(c, grade: .good, now: now)
        #expect(c.intervalDays == 3)
        c = Scheduler.review(c, grade: .good, now: now)
        #expect(c.intervalDays > 3)
        #expect(c.due > now)
    }

    @Test func againResetsAndCountsLapse() {
        let now = Date()
        var c = Scheduler.review(nil, grade: .good, now: now)
        c = Scheduler.review(c, grade: .good, now: now)
        c = Scheduler.review(c, grade: .again, now: now)
        #expect(c.reps == 0)
        #expect(c.lapses == 1)
        #expect(c.intervalDays == 0)
        #expect(c.due < now.addingTimeInterval(3600))
        #expect(c.ease < 2.5)
    }
}

@Suite struct ProgressTests {
    @Test func decodesOldFilesWithMissingKeys() throws {
        let json = #"{"cards":{},"settings":{"currentLevel":3}}"#
        let p = try JSONDecoder().decode(LearnerProgress.self, from: Data(json.utf8))
        #expect(p.settings.currentLevel == .l3)
        #expect(p.settings.dailyNewWords == 20)
        #expect(p.readings.isEmpty)
    }

    @Test func roundTripsThroughFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var p = LearnerProgress()
        p.record(key: "word:w-decide", grade: .good, skill: .vocabulary)
        let file = ProgressFile(directory: dir)
        try file.save(p)
        let loaded = file.load()
        #expect(loaded.cards["word:w-decide"]?.reps == 1)
        #expect(loaded.daily[LearnerProgress.dayKey()]?.reviews == 1)
        #expect(loaded.streak() == 1)
    }
}

@Suite struct ContentTests {
    let packs = repoRoot.appendingPathComponent("Content/packs")

    @Test func bundledContentIsValid() {
        let lib = ContentLibrary(directories: [packs])
        #expect(lib.loadErrors.isEmpty, "\(lib.loadErrors)")
        #expect(lib.validate().isEmpty, "\(lib.validate())")
        #expect(lib.words.count > 0)
        #expect(!lib.units(for: .grammar).isEmpty)
        #expect(!lib.passages.isEmpty)
    }

    @Test func manifestMatchesPacks() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Content/manifest.json"))
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: data)
        for entry in manifest.packs {
            let packData = try Data(contentsOf: repoRoot.appendingPathComponent("Content").appendingPathComponent(entry.file))
            #expect(ContentUpdater.sha256(packData) == entry.sha256, "manifest が古い: \(entry.file)（eigo-tool manifest を実行）")
            #expect(try ContentLibrary.decodePack(data: packData).revision == entry.revision)
        }
        #expect(manifest.packs.count == ContentLibrary.packFiles(in: packs).count)
    }

    @Test func newerRevisionWins() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func pack(_ rev: Int, _ word: String) -> String {
            #"{"schemaVersion":1,"id":"t","revision":\#(rev),"skill":"vocabulary","title":"t","words":[{"id":"w","headword":"\#(word)","pos":"名","meanings":["x"],"level":1}]}"#
        }
        let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try pack(1, "old").write(to: a.appendingPathComponent("t.json"), atomically: true, encoding: .utf8)
        try pack(2, "new").write(to: b.appendingPathComponent("t.json"), atomically: true, encoding: .utf8)
        #expect(ContentLibrary(directories: [a, b]).words.first?.headword == "new")
        #expect(ContentLibrary(directories: [b, a]).words.first?.headword == "new")
    }

    @Test func rejectsFutureSchema() {
        let json = #"{"schemaVersion":99,"id":"t","revision":1,"skill":"vocabulary","title":"t"}"#
        #expect(throws: ContentError.self) { try ContentLibrary.decodePack(data: Data(json.utf8)) }
    }

    @Test func plannerBuildsSession() {
        let lib = ContentLibrary(directories: [packs])
        var p = LearnerProgress()
        p.settings.dailyNewWords = 5
        p.settings.dailyNewExercises = 4
        let items = StudyPlanner(library: lib, progress: p).todaysSession()
        #expect(items.filter { $0.skill == .vocabulary }.count == 5)
        #expect(items.count == 9)
        #expect(Set(items.map(\.key)).count == items.count)
    }
}

@Suite struct VersionTests {
    @Test func comparesVersions() {
        #expect(ContentUpdater.compareVersions("1.2.0", "v1.10") == .orderedAscending)
        #expect(ContentUpdater.compareVersions("2.0", "1.9.9") == .orderedDescending)
        #expect(ContentUpdater.compareVersions("1.0", "1.0.0") == .orderedSame)
    }

    @Test func parsesFeedbackWrappedInText() throws {
        let text = """
        Here is the result:
        {"content":4,"organization":3,"vocabulary":4,"grammar":3,"estimatedScore":72,"overall":"良い","corrections":[{"original":"a","corrected":"b","explanation":"c"}],"revisedText":"x","advice":["y"]}
        """
        let f = try EssayGrader.parseFeedback(text)
        #expect(f.estimatedScore == 72)
        #expect(f.corrections.count == 1)
    }
}

@Suite struct MockExamTests {
    let library = ContentLibrary(directories: [repoRoot.appendingPathComponent("Content/packs")])

    @Test func buildsAllSectionsForEveryLevel() {
        for level in Level.allCases {
            let exam = MockExamBuilder(library: library).build(level: level, seed: 42)
            let kinds = exam.sections.map(\.kind)
            #expect(kinds == ExamSectionKind.allCases, "\(level): \(kinds)")
            #expect(MockExamScorer.maxScore(exam) == 100)
            #expect(exam.timeLimitMinutes == MockExam.timeLimit(for: level))
            // 試験内の問題IDは一意
            #expect(Set(exam.allItems.map(\.id)).count == exam.allItems.count)
            // 語彙問題は正解を含む4択
            for item in exam.sections[0].items {
                #expect(item.exercise.choices?.count == 4)
                #expect(item.exercise.choices?.contains(item.exercise.answers[0]) == true)
            }
            #expect(exam.sections.first { $0.kind == .reading }?.passage?.level == level)
        }
    }

    @Test func sameSeedGivesSameExam() {
        let b = MockExamBuilder(library: library)
        let a = b.build(level: .l4, seed: 7), c = b.build(level: .l4, seed: 7), d = b.build(level: .l4, seed: 8)
        #expect(a.allItems.map(\.exercise.id) == c.allItems.map(\.exercise.id))
        #expect(a.allItems.map(\.exercise.id) != d.allItems.map(\.exercise.id))
    }

    @Test func scoresSections() {
        let exam = MockExamBuilder(library: library).build(level: .l3, seed: 3)
        let grammar = exam.sections.first { $0.kind == .grammar }!
        var answers: [String: String] = [:]
        for (i, item) in grammar.items.enumerated() where i < grammar.items.count / 2 {
            answers[item.id] = item.exercise.answers[0]
        }
        let half = Double(grammar.items.count / 2) / Double(grammar.items.count)
        #expect(abs(MockExamScorer.sectionScore(grammar, answers: answers, selfScores: [:], compositionScore: nil) - 20 * half) < 0.001)

        let comp = exam.sections.first { $0.kind == .composition }!
        #expect(MockExamScorer.sectionScore(comp, answers: [:], selfScores: [:], compositionScore: 0.6) == 9)

        // 自己採点問題：空欄は自己採点を付けても0点
        let tr = ExamItem(id: "x", exercise: Exercise(id: "t", type: .translateToJa, prompt: "", sentence: "A", choices: nil,
                          answers: ["a"], explanation: "", hint: nil, keyPoints: nil, level: nil, tags: nil, media: nil),
                          sourceKey: "ex:t", skill: .construction)
        #expect(MockExamScorer.points(tr, answer: "", selfScore: 1) == 0)
        #expect(MockExamScorer.points(tr, answer: "訳", selfScore: 0.5) == 0.5)
    }

    @Test func oldProgressWithoutExamsStillLoads() throws {
        let p = try JSONDecoder().decode(LearnerProgress.self, from: Data(#"{"cards":{}}"#.utf8))
        #expect(p.mockExams.isEmpty)
    }
}

@Suite struct ReleaseConsistencyTests {
    @Test func manifestDoesNotRequireNewerAppThanThisRelease() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Content/manifest.json"))
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: data)
        let appVersion = try String(contentsOf: repoRoot.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let min = manifest.minAppVersion {
            // minAppVersion がアプリより新しいと、配布済みアプリがコンテンツ更新を受け取れなくなる
            #expect(ContentUpdater.compareVersions(min, appVersion) != .orderedDescending,
                    "manifest の minAppVersion \(min) が VERSION \(appVersion) より新しい")
        }
    }
}
