import Foundation

/// Writes notes as markers in Final Cut Pro 7 XML (xmeml), which Premiere Pro imports via File > Import.
/// The layout follows the marker files editingtools.io's Timecode Notes produces.
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
        // The matte clip runs from the sequence start to a little past the last marker.
        let duration = (markers.map(\.frame).max() ?? 0) + 1000
        let rateXML = "<rate><timebase>\(rate.timebase)</timebase><ntsc>\(rate.isNTSC ? "TRUE" : "FALSE")</ntsc></rate>"
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: false).timeSeparator(.omitted))

        // Premiere only shows the markers when the sequence has a clip in it, so the markers are written
        // twice: on a transparent colour matte spanning the sequence, and on the sequence itself.
        func markerXML(indent: String) -> String {
            markers.map { frame, note in
                // A shortcut's label becomes the marker name with its text as the comment;
                // a typed note becomes the marker name on its own.
                let name = note.name.isEmpty ? note.text : note.name
                let comment = note.name.isEmpty ? "" : note.text
                return """
                \(indent)<marker>
                \(indent)  <comment>\(escape(comment))</comment>
                \(indent)  <name>\(escape(name))</name>
                \(indent)  <in>\(frame)</in>
                \(indent)  <out>-1</out>
                \(indent)  <pproColor>\(note.color.pproColor)</pproColor>
                \(indent)</marker>

                """
            }.joined()
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
          <sequence id="sequence" explodedTracks="true">
            <uuid>\(UUID().uuidString.lowercased())</uuid>
            <duration>\(duration)</duration>
            \(rateXML)
            <name>\(escape(projectName))</name>
            <media>
              <video>
                <format>
                  <samplecharacteristics>
                    \(rateXML)
                    <width>1920</width>
                    <height>1080</height>
                    <anamorphic>FALSE</anamorphic>
                    <pixelaspectratio>square</pixelaspectratio>
                    <fielddominance>none</fielddominance>
                    <colordepth>24</colordepth>
                  </samplecharacteristics>
                </format>
                <track>
                  <enabled>TRUE</enabled>
                  <locked>FALSE</locked>
                  <generatoritem id="clipitem-1">
                    <name>Marker Color Matte (\(stamp))</name>
                    <enabled>TRUE</enabled>
                    <duration>\(duration)</duration>
                    \(rateXML)
                    <start>0</start>
                    <end>\(duration)</end>
                    <in>0</in>
                    <out>\(duration)</out>
                    <alphatype>none</alphatype>
                    <effect>
                      <name>Color</name>
                      <effectid>Color</effectid>
                      <effectcategory>Matte</effectcategory>
                      <effecttype>generator</effecttype>
                      <mediatype>video</mediatype>
                      <parameter authoringApp="PremierePro">
                        <parameterid>fillcolor</parameterid>
                        <name>Color</name>
                        <value>
                          <alpha>0</alpha>
                          <red>0</red>
                          <green>0</green>
                          <blue>0</blue>
                        </value>
                      </parameter>
                    </effect>
                    <filter>
                      <effect>
                        <name>Opacity</name>
                        <effectid>opacity</effectid>
                        <effectcategory>motion</effectcategory>
                        <effecttype>motion</effecttype>
                        <mediatype>video</mediatype>
                        <pproBypass>false</pproBypass>
                        <parameter authoringApp="PremierePro">
                          <parameterid>opacity</parameterid>
                          <name>opacity</name>
                          <valuemin>0</valuemin>
                          <valuemax>100</valuemax>
                          <value>0</value>
                        </parameter>
                      </effect>
                    </filter>
        \(markerXML(indent: "            "))\
                  </generatoritem>
                </track>
              </video>
              <audio>
                <numOutputChannels>2</numOutputChannels>
                <format>
                  <samplecharacteristics>
                    <depth>16</depth>
                    <samplerate>48000</samplerate>
                  </samplecharacteristics>
                </format>
                <outputs>
                  <groups>
                    <index>1</index>
                    <numchannels>1</numchannels>
                    <downmix>0</downmix>
                    <channel>
                      <index>1</index>
                    </channel>
                  </groups>
                  <groups>
                    <index>2</index>
                    <numchannels>1</numchannels>
                    <downmix>0</downmix>
                    <channel>
                      <index>2</index>
                    </channel>
                  </groups>
                </outputs>
                <track premiereTrackType="Stereo" currentExplodedTrackIndex="0" totalExplodedTrackCount="2">
                  <enabled>TRUE</enabled>
                  <locked>FALSE</locked>
                  <outputchannelindex>1</outputchannelindex>
                </track>
                <track premiereTrackType="Stereo" currentExplodedTrackIndex="1" totalExplodedTrackCount="2">
                  <enabled>TRUE</enabled>
                  <locked>FALSE</locked>
                  <outputchannelindex>2</outputchannelindex>
                </track>
              </audio>
            </media>
            <timecode>
              \(rateXML)
              <string>\(sequenceStart.string)</string>
              <frame>\(startFrame)</frame>
              <displayformat>\(rate.isDropFrame ? "DF" : "NDF")</displayformat>
            </timecode>
        \(markerXML(indent: "    "))\
          </sequence>
        </xmeml>

        """
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
