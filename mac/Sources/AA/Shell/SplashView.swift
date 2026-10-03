// Spec: 03 SHELL-003 (splash: Splash.png 560×632 on white, 1-px #DDDDDD border, text fallback, 2.4 s, no
//       click-to-dismiss), §6.1 (plain floating window, centred; 0.2 s fade allowed), 01 DATA-001, SHELL-198 (missing
//       resource → fallback).
import AppKit
import SwiftUI
import AACore

struct SplashView: View {
    @State private var shown = false
    private let image: NSImage? = AAResources.url(name: "Splash", ext: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 560, maxHeight: 640)
                    .frame(width: 560, height: 632)
            } else {
                fallback
            }
        }
        .background(Color.white)
        .overlay(Rectangle().strokeBorder(AAColor.Status.splashBorder, lineWidth: 1))
        .environment(\.colorScheme, .light)                 // the splash is hard-coded white (SHELL-002)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
        .accessibilityLabel("AA — A tool for Active minds — Created by B.E.P Avida — May 2026")
    }

    /// SHELL-003 fallback: a 520-wide panel, margins 40,34,40,34.
    private var fallback: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AA")
                .font(.system(size: 128, weight: .bold))
                .foregroundStyle(.black)
                .padding(.bottom, 18)
            ForEach(["A tool for Active minds", "Created by B.E.P Avida", "May 2026"], id: \.self) { line in
                Text(line).font(.aaMono(28)).italic().foregroundStyle(.black)
            }
        }
        .frame(width: 520, alignment: .leading)
        .padding(EdgeInsets(top: 34, leading: 40, bottom: 34, trailing: 40))
    }
}
