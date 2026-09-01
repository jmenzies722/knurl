import SwiftUI

struct ImmediatePressStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ImmediatePressLabel(configuration: configuration)
    }
}

private struct ImmediatePressLabel: View {
    let configuration: PrimitiveButtonStyle.Configuration
    @State private var pressed = false

    var body: some View {
        configuration.label
            .opacity(pressed ? 0.82 : 1)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.16), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            configuration.trigger()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                    }
            )
    }
}
