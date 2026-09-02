import KnurlCore
import SwiftUI

struct OutputSwitcher: View {
    @Bindable var state: DialState
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.outputName)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        Text(state.outputKind)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: currentSymbol)
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(HubTint.face(.output, progress: 0.5, muted: false))
                }
            }

            HomePodRouteButton(nearby: OutputWatch.shared.airPlayNearby)

            if !groups.isEmpty {
                ForEach(groups, id: \.transport) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.transport.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        if compact {
                            compactRow(group.devices)
                        } else {
                            ForEach(group.devices) { device in
                                deviceRow(device)
                            }
                        }
                    }
                }
            } else {
                Text("No speakers yet. Connect Bluetooth in Settings, or use HomePod & AirPlay above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                HubGlassButton(
                    title: state.swapLabel,
                    symbol: "arrow.triangle.2.circlepath",
                    tint: HubTint.face(.output, progress: 0.5, muted: false)
                ) {
                    state.swapSpeaker()
                }
                if !compact {
                    HubGlassButton(title: "Bluetooth", symbol: "antenna.radiowaves.left.and.right") {
                        state.openBluetoothSettings()
                    }
                    HubGlassButton(title: "Sound", symbol: "slider.horizontal.3") {
                        state.openSoundSettings()
                    }
                }
            }

            if let memory = state.outputMemoryLine {
                Text(memory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentSymbol: String {
        state.outputDevices.first { $0.uid == state.outputUID }?.transport.symbol
            ?? "hifispeaker.fill"
    }

    private var groups: [(transport: AudioTransport, devices: [AudioDevice])] {
        let order: [AudioTransport] = [
            .bluetooth, .airPlay, .builtIn, .hdmi, .displayPort, .usb, .thunderbolt, .virtual, .unknown,
        ]
        return order.compactMap { transport in
            let devices = state.outputDevices.filter { $0.transport == transport }
            return devices.isEmpty ? nil : (transport, devices)
        }
    }

    private func deviceRow(_ device: AudioDevice) -> some View {
        let selected = device.uid == state.outputUID
        return HStack(spacing: 12) {
            Image(systemName: device.transport.symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? HubTint.face(.output, progress: 0.5, muted: false) : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.callout.weight(selected ? .semibold : .regular))
                Text(device.transport.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HubTint.face(.output, progress: 0.5, muted: false))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(
            selected
                ? .regular.tint(HubTint.face(.output, progress: 0.5, muted: false).opacity(0.32)).interactive()
                : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(ImmediatePress(action: { state.selectOutput(device) }))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel("\(device.name), \(device.transport.title)")
    }

    private func compactRow(_ devices: [AudioDevice]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(devices) { device in
                    let selected = device.uid == state.outputUID
                    HStack(spacing: 6) {
                        Image(systemName: device.transport.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(device.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassEffect(
                        selected
                            ? .regular.tint(HubTint.face(.output, progress: 0.5, muted: false).opacity(0.4)).interactive()
                            : .regular.interactive(),
                        in: Capsule()
                    )
                    .overlay(ImmediatePress(action: { state.selectOutput(device) }))
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .frame(height: 36)
    }
}
