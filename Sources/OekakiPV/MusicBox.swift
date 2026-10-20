import Foundation

/// The film's music, made from sine waves: a music box over soft chords,
/// IV–V–iii–vi in C, a quiet bass and a light tick while the picture is made,
/// the tune in full over the finished picture, and C to end.
enum MusicBox {
    static let rate = 44_100

    struct Note {
        var beat: Double
        var midi: Int
        var beats: Double
        var loud: Double
    }

    /// Writes the music, `length` seconds long, as a 16-bit stereo WAV file.
    /// `climax` is when the tune comes in; the bars are timed so it starts on one.
    static func write(to url: URL, length: Double, climax: Double, ending: Double) throws {
        // Bars of four beats; the climax falls on the start of bar 24.
        let bar = climax / 24
        let beat = bar / 4
        let count = Int(length * Double(rate))
        var left = [Double](repeating: 0, count: count)
        var right = [Double](repeating: 0, count: count)
        let chords: [[Int]] = [[53, 57, 60], [55, 59, 62], [52, 55, 59], [57, 60, 64]]  // F, G, Em, Am
        let finalChord = [48, 55, 60, 64]
        let endBar = Int(ending / bar)

        func seconds(_ beats: Double) -> Double { beats * beat }
        func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

        func add(_ samples: [Double], at time: Double, pan: Double) {
            let start = Int(time * Double(rate))
            let l = sqrt(0.5 * (1 - pan)), r = sqrt(0.5 * (1 + pan))
            for (index, value) in samples.enumerated() {
                let i = start + index
                guard i >= 0, i < count else { continue }
                left[i] += value * l
                right[i] += value * r
            }
        }

        // A music-box tine: a bright attack, overtones that die fast.
        func tine(_ midi: Int, loud: Double) -> [Double] {
            let f = frequency(midi)
            let n = Int(2.4 * Double(rate))
            return (0..<n).map { i in
                let t = Double(i) / Double(rate)
                let attack = min(1, t / 0.004)
                let body = sin(2 * .pi * f * t) * exp(-t / 0.9)
                let shine = 0.32 * sin(2 * .pi * f * 2 * t) * exp(-t / 0.35) + 0.12 * sin(2 * .pi * f * 3.01 * t) * exp(-t / 0.18)
                return loud * attack * (body + shine)
            }
        }

        // A soft pad: slightly detuned, rounded waves, swelling in and out.
        func pad(_ midis: [Int], length: Double, loud: Double) -> [Double] {
            let n = Int(length * Double(rate))
            return (0..<n).map { i in
                let t = Double(i) / Double(rate)
                let envelope = min(1, t / 0.6) * min(1, (length - t) / 0.8)
                var value = 0.0
                for midi in midis {
                    let f = frequency(midi)
                    for detune in [-0.003, 0.003] {
                        let g = f * (1 + detune)
                        value += sin(2 * .pi * g * t) + sin(2 * .pi * g * 3 * t) / 12 + sin(2 * .pi * g * 5 * t) / 40
                    }
                }
                return loud * max(0, envelope) * value / Double(midis.count * 2)
            }
        }

        // A round bass note.
        func bass(_ midi: Int, length: Double, loud: Double) -> [Double] {
            let f = frequency(midi)
            let n = Int(length * Double(rate))
            return (0..<n).map { i in
                let t = Double(i) / Double(rate)
                let envelope = min(1, t / 0.01) * exp(-t / 1.2) * min(1, (length - t) / 0.05)
                return loud * max(0, envelope) * (sin(2 * .pi * f * t) + 0.25 * sin(2 * .pi * f * 2 * t))
            }
        }

        // A light tick, like a brushed hat.
        var noise = SplitMix(seed: 3)
        func tick(loud: Double) -> [Double] {
            let n = Int(0.06 * Double(rate))
            var previous = 0.0
            return (0..<n).map { i in
                let t = Double(i) / Double(rate)
                let white = Double(noise.next()) * 2 - 1
                let bright = white - previous
                previous = white
                return loud * bright * exp(-t / 0.008)
            }
        }

        // The tune, two bars to a line, over the four chords.
        let tune: [Note] = [
            Note(beat: 0, midi: 81, beats: 1, loud: 1), Note(beat: 1, midi: 84, beats: 0.5, loud: 0.9), Note(beat: 1.5, midi: 81, beats: 0.5, loud: 0.8),
            Note(beat: 2, midi: 79, beats: 1, loud: 0.9), Note(beat: 3, midi: 77, beats: 1, loud: 0.8),
            Note(beat: 4, midi: 79, beats: 1, loud: 1), Note(beat: 5, midi: 83, beats: 0.5, loud: 0.9), Note(beat: 5.5, midi: 86, beats: 0.5, loud: 0.9),
            Note(beat: 6, midi: 83, beats: 2, loud: 0.9),
            Note(beat: 8, midi: 88, beats: 1, loud: 1), Note(beat: 9, midi: 86, beats: 0.5, loud: 0.9), Note(beat: 9.5, midi: 83, beats: 0.5, loud: 0.8),
            Note(beat: 10, midi: 79, beats: 1, loud: 0.9), Note(beat: 11, midi: 76, beats: 1, loud: 0.8),
            Note(beat: 12, midi: 81, beats: 1.5, loud: 1), Note(beat: 13.5, midi: 83, beats: 0.5, loud: 0.8), Note(beat: 14, midi: 84, beats: 2, loud: 1),
        ]

        for index in 0..<endBar {
            let start = Double(index) * bar
            let chord = chords[index % 4]
            let studio = index >= 3 && index < 24
            let climax = index >= 24
            // The chords, soft, under everything.
            add(pad(chord.map { $0 + 12 }, length: bar + 0.6, loud: climax ? 0.16 : 0.11), at: start, pan: 0)
            // The music box rolls up and down the chord.
            let pattern = [0, 1, 2, 3, 2, 1, 2, 3].map { step -> Int in
                let notes = chord.map { $0 + 24 } + [chord[0] + 36]
                return notes[step]
            }
            for (k, midi) in pattern.enumerated() where index >= 1 || k % 2 == 0 {
                let loud = (k % 2 == 0 ? 0.16 : 0.11) * (climax ? 0.8 : 1)
                add(tine(midi, loud: loud), at: start + seconds(Double(k) * 0.5), pan: k % 2 == 0 ? -0.35 : 0.35)
            }
            if studio || climax {
                add(bass(chord[0] - 12, length: seconds(2), loud: 0.22), at: start, pan: 0)
                add(bass(chord[2] - 24, length: seconds(2), loud: 0.18), at: start + seconds(2), pan: 0)
                for k in 0..<8 {
                    add(tick(loud: k % 2 == 1 ? 0.03 : 0.014), at: start + seconds(Double(k) * 0.5), pan: 0.2)
                }
            }
            // The tune: quietly once in the middle, in full over the finished picture.
            let tuneStart = index - (climax ? 24 : 12)
            if (climax || (index >= 12 && index < 16)), tuneStart >= 0, tuneStart < 4 {
                let loud = climax ? 0.34 : 0.16
                for note in tune where note.beat >= Double(tuneStart * 4) && note.beat < Double(tuneStart * 4 + 4) {
                    add(tine(note.midi, loud: loud * note.loud), at: start + seconds(note.beat - Double(tuneStart * 4)), pan: 0.05)
                    add(tine(note.midi + 12, loud: loud * note.loud * 0.2), at: start + seconds(note.beat - Double(tuneStart * 4)) + 0.01, pan: -0.1)
                }
            }
        }
        // C to end, left to ring.
        let last = Double(endBar) * bar
        add(pad(finalChord.map { $0 + 12 }, length: length - last, loud: 0.15), at: last, pan: 0)
        for (k, midi) in (finalChord.map { $0 + 24 } + [84]).enumerated() {
            add(tine(midi, loud: 0.18), at: last + Double(k) * 0.09, pan: Double(k % 2) * 0.6 - 0.3)
        }
        add(bass(36, length: length - last, loud: 0.2), at: last, pan: 0)

        // A little room round it all: a few echoes, fading.
        for (delay, gain, cross) in [(0.083, 0.22, true), (0.127, 0.18, false), (0.211, 0.12, true), (0.337, 0.08, false)] {
            let offset = Int(delay * Double(rate))
            for i in stride(from: count - 1, through: offset, by: -1) {
                let l = left[i - offset], r = right[i - offset]
                left[i] += gain * (cross ? r : l)
                right[i] += gain * (cross ? l : r)
            }
        }

        // Fade in and out, then make the loudest point just under full.
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let fade = min(1, t / 0.4) * min(1, (length - t) / 1.5)
            left[i] *= fade
            right[i] *= fade
        }
        let peak = max(left.map(abs).max() ?? 1, right.map(abs).max() ?? 1, 0.0001)
        let scale = 0.89 / peak

        var data = Data()
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put32(UInt32(36 + count * 4))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put32(16); put16(1); put16(2); put32(UInt32(rate)); put32(UInt32(rate * 4)); put16(4); put16(16)
        data.append(contentsOf: Array("data".utf8))
        put32(UInt32(count * 4))
        data.reserveCapacity(44 + count * 4)
        for i in 0..<count {
            put16(UInt16(bitPattern: Int16(max(-32767, min(32767, left[i] * scale * 32767)))))
            put16(UInt16(bitPattern: Int16(max(-32767, min(32767, right[i] * scale * 32767)))))
        }
        try data.write(to: url)
    }
}
