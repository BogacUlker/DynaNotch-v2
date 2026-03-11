//
//  LottieAnimationContainer.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 29..
//

import SwiftUI
import Defaults

struct LottieAnimationContainer: View {
    @Default(.selectedVisualizer) var selectedVisualizer
    var body: some View {
        if let vis = selectedVisualizer {
            LottieView(url: vis.url, speed: vis.speed, loopMode: .loop)
        } else if let defaultURL = URL(string: "https://assets9.lottiefiles.com/packages/lf20_mniampqn.json") {
            LottieView(url: defaultURL, speed: 1.0, loopMode: .loop)
        }
    }
}

#Preview {
    LottieAnimationContainer()
}
