import Foundation

@main struct TestLyrics {
    static func main() {
        let source = "[00:01.25]Prima riga\n[00:03.50]Seconda riga\n[01:04]Terza riga"
        let parsed = LyricsService.parseLRC(source)
        precondition(parsed.count == 3)
        precondition(abs(parsed[0].time - 1.25) < 0.001)
        precondition(abs(parsed[1].time - 3.5) < 0.001)
        precondition(abs(parsed[2].time - 64.0) < 0.001)
        print("OK: parsing testi sincronizzati LRC")
    }
}
