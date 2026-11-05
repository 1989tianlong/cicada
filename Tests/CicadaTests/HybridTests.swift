import Foundation
import Testing
@testable import Cicada

@Suite struct EchoMatchTests {
    private func h(_ t: String, _ s: Double, _ e: Double) -> EchoMatch.Heard { .init(text: t, start: s, end: e) }

    @Test func theRoomsCopyOfARemoteSentenceIsAnEcho() {
        let online = [h("Revenue grew by 12%, mostly from the new region.", 10, 14)]
        // Heard worse from the speakers, and a word lost.
        #expect(EchoMatch.isEcho(h("revenue grew by 12% mostly from new region", 10.3, 14.2), online: online))
    }

    @Test func cutDifferentlyStillMatches() {
        let online = [h("我们先看一下这个季度的数据。", 0, 2), h("收入增长了百分之十二，主要来自新的市场。", 2.2, 5)]
        #expect(EchoMatch.isEcho(h("这个季度的数据收入增长了百分之十二", 0.8, 4), online: online))
    }

    @Test func roomSpeechIsKept() {
        let online = [h("Revenue grew by 12%, mostly from the new region.", 10, 14)]
        #expect(!EchoMatch.isEcho(h("I think we should check the numbers for Europe first", 11, 15), online: online))
        #expect(!EchoMatch.isEcho(h("我觉得应该先看一下欧洲的情况", 11, 15), online: online))
    }

    @Test func theSameWordsLongAfterAreNotAnEcho() {
        let online = [h("Can everyone hear me okay?", 0, 2)]
        #expect(!EchoMatch.isEcho(h("can everyone hear me okay", 20, 22), online: online))
    }

    @Test func shortLinesMatchOnlyExactly() {
        let online = [h("OK.", 5, 5.5)]
        #expect(EchoMatch.isEcho(h("ok", 5.2, 5.6), online: online))
        #expect(!EchoMatch.isEcho(h("no", 5.2, 5.6), online: online))
    }

    @Test func gateClosesForTheHang() {
        let g = EchoGate()
        #expect(!g.closed(now: 100))
        g.hold(now: 100)
        #expect(g.closed(now: 100.3))
        #expect(!g.closed(now: 100 + EchoGate.hang + 0.01))
    }
}

@Suite struct VoiceGateBlockTests {
    /// The echo-cancelling unit's ~11 ms blocks learn the room's floor per second, as the mic tap's do.
    @Test func smallBlocksLearnTheFloorPerSecond() {
        var g = VoiceGate(adaptive: true)
        let block = 171.0 / 16000
        // Ten seconds of talk at 0.012, one quiet block (0.002) in each second.
        for i in 0..<Int(10 / block) { _ = g.voiced(i % 94 == 0 ? 0.002 : 0.012, seconds: block) }
        #expect(g.threshold < 0.006)
        let voice = g.voiced(0.012, seconds: block)
        #expect(voice)
    }
}
