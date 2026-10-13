import Foundation

/// Writes notes as sequence markers in Final Cut Pro 7 XML (xmeml), which Premiere Pro imports
/// via File > Import as a sequence carrying the markers.
enum PremiereXML {
    static func make(projectName: String, notes: [Note], rate: FrameRate, sequenceStart: Timecode) -> String {
        let startFrame = sequenceStart.frameCount(rate: rate)
        let day = Timecode(hours: 23, minutes: 59, seconds: 59, frames: rate.timebase - 1,
                           dropFrame: rate.isDropFrame).frameCount(rate: rate) + 1
        let markers = notes.map { note -> (frame: Int, note: Note) in
            // Notes earlier than the sequence start are treated as being past midnight.
            let frame = note.timecode.frameCount(rate: rate) - startFrame
            return (frame < 0 ? frame + day : frame, note)
        }.sorted { $0.frame < $1.frame }
        let duration = (markers.map(\.frame).max() ?? 0) + rate.timebase * 10
        let rateXML = "<rate><timebase>\(rate.timebase)</timebase><ntsc>\(rate.isNTSC ? "TRUE" : "FALSE")</ntsc></rate>"

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
          <sequence id="sequence-1">
            <name>\(escape(projectName))</name>
            <duration>\(duration)</duration>
            \(rateXML)
            <timecode>
              \(rateXML)
              <string>\(sequenceStart.string)</string>
              <frame>\(startFrame)</frame>
              <displayformat>\(rate.isDropFrame ? "DF" : "NDF")</displayformat>
            </timecode>
            <media>
              <video>
                <format>
                  <samplecharacteristics>
                    \(rateXML)
                    <width>1920</width>
                    <height>1080</height>
                    <pixelaspectratio>square</pixelaspectratio>
                  </samplecharacteristics>
                </format>
                <track></track>
              </video>
              <audio>
                <track></track>
              </audio>
            </media>

        """
        for (frame, note) in markers {
            // A shortcut's label becomes the marker name with its text as the comment;
            // a typed note becomes the marker name on its own.
            let name = note.name.isEmpty ? note.text : note.name
            let comment = note.name.isEmpty ? "" : note.text
            xml += """
                <marker>
                  <name>\(escape(name))</name>
                  <comment>\(escape(comment))</comment>
                  <in>\(frame)</in>
                  <out>-1</out>
                  <pproColor>\(note.color.pproColor)</pproColor>
                </marker>

            """
        }
        xml += """
          </sequence>
        </xmeml>

        """
        return xml
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
