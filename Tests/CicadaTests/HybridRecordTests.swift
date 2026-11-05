import Foundation
import Testing
@testable import Cicada

@Suite struct HybridRecordTests {
    private func line(_ id: String, _ speaker: String = "them", via: String? = nil) -> TranscriptLine {
        TranscriptLine(id: id, t: 0, speaker: speaker, src: "x", srcLang: "en", dstLang: "zh", via: via)
    }

    @Test func onlyAMeetingThatHeardBothShowsPlaces() {
        #expect(!RecordList.heardBoth([line("a"), line("b")]))
        #expect(!RecordList.heardBoth([line("a", via: "room"), line("b", via: "room")]))
        // Your own lines (the talk key) don't make it a meeting that heard the Mac.
        #expect(!RecordList.heardBoth([line("a", via: "room"), line("b", "me")]))
        #expect(RecordList.heardBoth([line("a", via: "room"), line("b")]))
    }

    @Test func aChangeOfPlaceStartsANewRun() {
        let ls = [line("a"), line("b"), line("c", via: "room"), line("d", "me"), line("e", via: "room"), line("f")]
        #expect(RecordList.placeStarts(ls) == ["a", "c", "e", "f"])
    }

    @Test func onlinePromptAsksOnlyInTheRoomDuringACall() {
        #expect(RoomPrompt.asksOnline(roomOnly: true, bothAvailable: true, answered: false, inCall: true))
        #expect(!RoomPrompt.asksOnline(roomOnly: true, bothAvailable: true, answered: false, inCall: false))
        #expect(!RoomPrompt.asksOnline(roomOnly: true, bothAvailable: true, answered: true, inCall: true))
        // macOS 14/15 can't hear both: don't offer it.
        #expect(!RoomPrompt.asksOnline(roomOnly: true, bothAvailable: false, answered: false, inCall: true))
        #expect(!RoomPrompt.asksOnline(roomOnly: false, bothAvailable: true, answered: false, inCall: true))
    }

    @Test func noteSaysHowTheRoomIsHeard() {
        #expect(HybridNote.line(roomRunning: true, echoCancelled: true, headsetDefault: false) == nil)
        #expect(HybridNote.line(roomRunning: false, echoCancelled: false, headsetDefault: true) == nil)
        #expect(HybridNote.line(roomRunning: true, echoCancelled: false, headsetDefault: true) == L("线上有人说话时，先不听会议室"))
        #expect(HybridNote.line(roomRunning: true, echoCancelled: true, headsetDefault: true) == L("用 Mac 麦克风听会议室"))
    }
}
