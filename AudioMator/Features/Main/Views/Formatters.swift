import Foundation

func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%02d:%02d", total / 60, total % 60)
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
    guard hz > 0 else { return "" }
    return "\(Int(hz.rounded())) Hz"
}

func formatChannelCount(_ channels: Int) -> String {
    guard channels > 0 else { return "" }
    return "\(channels)"
}
