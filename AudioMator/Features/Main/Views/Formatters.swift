import Foundation

func formatDuration(_ seconds: Double) -> String {
    guard seconds > 0,
          let total = AudioNumericConversion.roundedInt(seconds, rule: .down) else {
        return "00:00"
    }
    return "\(zeroPadded(total / 60)):\(zeroPadded(total % 60))"
}

private func zeroPadded(_ value: Int) -> String {
    let text = String(value)
    return text.count >= 2 ? text : "0\(text)"
}

func formatTrackIndex(_ number: Int, total: Int) -> String {
    guard number > 0 else { return "" }

    if total > 0 {
        return "\(number)/\(total)"
    }

    return "\(number)"
}

func formatBitrate(_ kbps: Int) -> String {
    guard kbps > 0 else { return "" }
    return "\(kbps) kbps"
}

func formatSampleRate(_ hz: Double) -> String {
    guard hz > 0,
          let rounded = AudioNumericConversion.roundedInt(hz) else {
        return ""
    }
    return "\(rounded) Hz"
}

func formatChannelCount(_ channels: Int) -> String {
    guard channels > 0 else { return "" }
    return "\(channels)"
}
